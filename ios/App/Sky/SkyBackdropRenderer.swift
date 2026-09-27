import MetalKit
import SkyCore
import SwiftUI

/// Per-frame inputs of the simulated-sky backdrop (see `SkyBackdropShader`).
struct SkyBackdropParams: Equatable {
    var intrinsics: SIMD4<Float>
    var camToRef: RotationMatrix
    var camToGal: RotationMatrix
    var sun: SIMD3<Double>
    var moon: SIMD3<Double>
    /// Sun altitude, Moon altitude, Moon phase angle (deg), dark zenith nL.
    var light: SIMD4<Float>
    /// Extinction k, Milky Way gain, field mode (0/1), exposure.
    var options: SIMD4<Float>
    var horizon: [Float]
}

/// Draws the simulated sky with Metal: one full-screen triangle whose
/// fragment shader evaluates SkyCore's sky models per pixel. The shader is
/// compiled from source at first use (Metal's runtime compiler), so the
/// build needs no offline Metal toolchain.
struct SkyBackdropView: UIViewRepresentable {
    let params: SkyBackdropParams

    func makeCoordinator() -> SkyBackdropRenderer { SkyBackdropRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: SkyBackdropRenderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.params = params
        view.setNeedsDisplay()
    }
}

final class SkyBackdropRenderer: NSObject, MTKViewDelegate {
    var params: SkyBackdropParams?

    static let device = MTLCreateSystemDefaultDevice()
    private static let pipeline: (any MTLRenderPipelineState)? = {
        guard let device, let library = try? device.makeLibrary(source: SkyBackdropShader.source, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "skyVertex")
        d.fragmentFunction = library.makeFunction(name: "skyFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: d)
    }()
    private static let queue = device?.makeCommandQueue()
    private static let milkyWay = MilkyWayModel.shaderParameters

    /// Compile ahead of the first frame (about 0.1 s).
    static func warmUp() { _ = pipeline }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let params, let pipeline = Self.pipeline, let queue = Self.queue,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        func row(_ a: Double, _ b: Double, _ c: Double) -> SIMD4<Float> { SIMD4(Float(a), Float(b), Float(c), 0) }
        func v(_ x: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(x.x), Float(x.y), Float(x.z), 0) }
        let r = params.camToRef, g = params.camToGal
        let pointsPerPixel = Float(view.bounds.width / max(view.drawableSize.width, 1))
        var u: [SIMD4<Float>] = [
            params.intrinsics,
            row(r.m11, r.m12, r.m13), row(r.m21, r.m22, r.m23), row(r.m31, r.m32, r.m33),
            row(g.m11, g.m12, g.m13), row(g.m21, g.m22, g.m23), row(g.m31, g.m32, g.m33),
            v(params.sun), v(params.moon), params.light, params.options,
            SIMD4(pointsPerPixel, Float(params.horizon.count), Float(Self.milkyWay.count), 0),
        ]
        var horizon = params.horizon
        var mw = Self.milkyWay
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<SIMD4<Float>>.stride * u.count, index: 0)
        encoder.setFragmentBytes(&horizon, length: MemoryLayout<Float>.stride * horizon.count, index: 1)
        encoder.setFragmentBytes(&mw, length: MemoryLayout<Float>.stride * mw.count, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Metal source for the backdrop. It evaluates the same formulas as SkyCore's
/// SkyBrightness.swift (Krisciunas & Schaefer dark sky and moonlight, the
/// hand-tuned twilight) and MilkyWayModel.swift (disk + star clouds − dust),
/// tone-mapped from nanolamberts to the screen, with the terrain skyline as
/// solid ground. Keep it in step with those files.
enum SkyBackdropShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// The simulated sky behind the Sky view's overlay, one pixel at a time:
// the same models as SkyCore's SkyBrightness.swift (Krisciunas & Schaefer
// dark sky and moonlight, the hand-tuned twilight) and MilkyWayModel.swift
// (disk + star clouds − dust), tone-mapped from nanolamberts to the screen,
// with the terrain skyline as solid ground. Keep in step with those files.

constant float kPi = 3.14159265358979f;
constant float kDeg = 180.0f / 3.14159265358979f;

static float ksAirmass(float zenithDeg) {
    float s = sin(clamp(zenithDeg, 0.0f, 90.0f) / kDeg);
    return rsqrt(1.0f - 0.96f * s * s);
}

static float kyAirmass(float altDeg) {
    float h = max(altDeg, -1.0f);
    return 1.0f / (sin(h / kDeg) + 0.50572f * pow(h + 6.07995f, -1.6364f));
}

static float wrapDeg(float x) {
    float r = fmod(x + 180.0f, 360.0f);
    return (r < 0.0f ? r + 360.0f : r) - 180.0f;
}

static float feature(constant float *f, float l, float b) {
    float dl = wrapDeg(l - f[0]);
    float db = b - f[1];
    return f[4] * exp(-(dl * dl / (2.0f * f[2] * f[2]) + db * db / (2.0f * f[3] * f[3])));
}

// MilkyWayModel.brightness: p[0] = star-cloud count, then (l, b, σl, σb, amp) rows.
static float milkyWay(float l, float b, constant float *p, int count) {
    float lw = wrapDeg(l);
    float amp = 0.16f + 0.30f * exp(-(lw / 55.0f) * (lw / 55.0f));
    float sigma = 3.0f + 3.0f * exp(-(lw / 45.0f) * (lw / 45.0f));
    float light = amp * (0.75f * exp(-b * b / (2.0f * sigma * sigma)) + 0.25f * exp(-abs(b) / (3.0f * sigma)));
    int clouds = int(p[0]);
    int rows = (count - 1) / 5;
    float tau = 0.5f * exp(-(lw / 70.0f) * (lw / 70.0f)) * exp(-b * b / 2.0f);
    for (int i = 0; i < rows; i++) {
        float g = feature(p + 1 + 5 * i, l, b);
        if (i < clouds) { light += g; } else { tau += g; }
    }
    return light * exp(-tau);
}


struct Uniforms {
    float4 intr;   // fx, fy, cx, cy in points
    float4 r0, r1, r2;  // camera -> reference rows
    float4 g0, g1, g2;  // camera -> galactic rows
    float4 sun, moon;   // reference-frame unit vectors
    float4 light;  // sun altitude, moon altitude, moon phase angle, dark zenith nL
    float4 opts;   // extinction k, Milky Way gain, field mode, exposure
    float4 misc;   // points per pixel, horizon count, Milky Way parameter count
};

struct VOut { float4 position [[position]]; };

vertex VOut skyVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.position = float4(p * 2.0f - 1.0f, 0.0f, 1.0f);
    return o;
}

fragment float4 skyFragment(VOut vin [[stage_in]], constant Uniforms &u [[buffer(0)]],
                            constant float *horizon [[buffer(1)]], constant float *mw [[buffer(2)]]) {
    float2 position = vin.position.xy * u.misc.x;
    float4 intr = u.intr;
    float3 sun = u.sun.xyz, moon = u.moon.xyz;
    float4 light = u.light, opts = u.opts;
    int hCount = int(u.misc.y), mwCount = int(u.misc.z);

    float3 cam = float3((position.x - intr.z) / intr.x, (position.y - intr.w) / intr.y, 1.0f);
    float3 ref = normalize(float3(dot(u.r0.xyz, cam), dot(u.r1.xyz, cam), dot(u.r2.xyz, cam)));
    float alt = asin(clamp(ref.z, -1.0f, 1.0f)) * kDeg;
    float az = atan2(-ref.y, ref.x) * kDeg;
    if (az < 0.0f) { az += 360.0f; }

    float terrain = horizon[0];
    if (hCount > 1) {
        float x = az * float(hCount) / 360.0f;
        int i0 = int(floor(x)) % hCount;
        int i1 = (i0 + 1) % hCount;
        terrain = mix(horizon[i0], horizon[i1], fract(x));
    }

    float k = opts.x;
    float sunAlt = light.x, moonAlt = light.y, phase = abs(light.z), darkZenith = light.w;
    float h = max(alt, terrain);  // the ground takes its light from the sky just above it
    float3 skyDir = alt < terrain ? normalize(float3(ref.x, ref.y, 0.0f) * cos(h / kDeg) / max(length(ref.xy), 1e-4f) + float3(0, 0, sin(h / kDeg))) : ref;

    // Natural sky (Krisciunas & Schaefer eq. 2).
    float xs = ksAirmass(90.0f - max(h, 0.0f));
    float dark = darkZenith * pow(10.0f, -0.4f * k * (xs - 1.0f)) * xs;

    // Moonlight (Krisciunas & Schaefer eqs. 15–21).
    float moonB = 0.0f;
    if (moonAlt > -1.0f) {
        float istar = pow(10.0f, -0.4f * (3.84f + 0.026f * phase + 4e-9f * pow(phase, 4.0f)));
        float rho = max(acos(clamp(dot(skyDir, moon), -1.0f, 1.0f)) * kDeg, 1.0f);
        float c = cos(rho / kDeg);
        float f = pow(10.0f, 5.36f) * (1.06f + c * c) + pow(10.0f, 6.15f - rho / 40.0f);
        float xm = ksAirmass(90.0f - max(moonAlt, 0.0f));
        moonB = f * istar * pow(10.0f, -0.4f * k * xm) * (1.0f - pow(10.0f, -0.4f * k * xs)) * min(1.0f, (moonAlt + 1.0f) / 2.0f);
    }

    // Twilight (SkyBrightness.twilight).
    float twB = 0.0f;
    float sunRho = acos(clamp(dot(skyDir, sun), -1.0f, 1.0f)) * kDeg;
    float hs = min(sunAlt, 10.0f);
    if (hs > -20.0f) {
        twB = 410.0f * pow(10.0f, 0.4f * (hs + 12.0f)) * (1.0f + 4.0f * exp(-sunRho / 35.0f)) * (1.0f + 2.0f * exp(-max(h, 0.0f) / 12.0f));
    }

    // Milky Way, dimmed by extinction like the stars.
    float mwB = 0.0f;
    if (opts.y > 0.0f && alt >= terrain) {
        float3 g = normalize(float3(dot(u.g0.xyz, cam), dot(u.g1.xyz, cam), dot(u.g2.xyz, cam)));
        float l = atan2(g.y, g.x) * kDeg;
        float b = asin(clamp(g.z, -1.0f, 1.0f)) * kDeg;
        mwB = opts.y * darkZenith * milkyWay(l, b, mw, mwCount) * pow(10.0f, -0.4f * k * (kyAirmass(alt) - 1.0f));
    }

    float total = dark + moonB + twB + mwB;
    // Log tone map: 25 nL (darker than any natural sky) → 0, a bright
    // daytime sky (4e7 nL) → 1, scaled by the exposure control.
    float v = clamp(log10(total / 25.0f) / log10(4e7f / 25.0f), 0.0f, 1.0f);
    v = pow(v, 0.85f) * opts.w;

    // Colour: each light source's share of the brightness.
    float warm = exp(-sunRho / 30.0f) * smoothstep(-14.0f, -2.0f, sunAlt) * exp(-max(h, 0.0f) / 20.0f);
    float3 twColor = mix(float3(0.35f, 0.55f, 1.0f), float3(1.0f, 0.55f, 0.25f), warm);
    float3 rgb = (dark * float3(0.45f, 0.52f, 0.75f) + moonB * float3(0.55f, 0.68f, 1.0f)
                  + twB * twColor + mwB * float3(1.0f, 0.95f, 0.86f)) / total;
    rgb = rgb / max(max(rgb.r, max(rgb.g, rgb.b)), 1e-4f) * v;

    if (alt < terrain) {
        // Solid ground: a dim silhouette lit a little by the same sky.
        rgb = float3(0.10f, 0.09f, 0.08f) * v * 0.9f + float3(0.012f, 0.011f, 0.010f);
    }
    if (opts.z > 0.5f) {
        float lum = dot(rgb, float3(0.40f, 0.45f, 0.15f));
        rgb = float3(lum * 0.9f, 0.0f, 0.0f);
    }
    return float4(rgb, 1.0f);
}
"""#
}
