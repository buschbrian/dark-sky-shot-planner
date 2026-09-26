import Foundation

public struct PixelPoint: Sendable, Hashable, Codable {
    public let u: Double
    public let v: Double

    public init(u: Double, v: Double) {
        self.u = u
        self.v = v
    }
}

/// Pinhole intrinsics of the back camera for the image as displayed in
/// portrait (frames 6–7 in SkyFrames.swift), in that image's pixels.
public struct CameraIntrinsics: Sendable, Hashable, Codable {
    public let fx: Double
    public let fy: Double
    public let cx: Double
    public let cy: Double
    public let width: Double
    public let height: Double

    public init(fx: Double, fy: Double, cx: Double, cy: Double, width: Double, height: Double) {
        precondition(fx > 0 && fy > 0 && width > 0 && height > 0, "focal lengths and size must be positive")
        (self.fx, self.fy, self.cx, self.cy, self.width, self.height) = (fx, fy, cx, cy, width, height)
    }

    /// Square pixels, principal point at the centre, from the field of view
    /// across the image's LONGER side (`AVCaptureDevice.Format.videoFieldOfView`
    /// is measured across the sensor's long side). A fallback when the
    /// intrinsic matrix is not delivered.
    public init(longSideFieldOfViewDeg fov: Double, width: Double, height: Double) {
        precondition(fov > 0 && fov < 180, "field of view must be in (0, 180)")
        let f = max(width, height) / 2 / tan(fov * .pi / 360)
        self.init(fx: f, fy: f, cx: width / 2, cy: height / 2, width: width, height: height)
    }

    /// Portrait intrinsics from those of the back camera's native landscape
    /// buffer (AVFoundation's intrinsic matrix, `[fx 0 cx; 0 fy cy; 0 0 1]`,
    /// is in buffer pixels). That buffer is the portrait image turned 90°
    /// counter-clockwise (`CGImagePropertyOrientation.right`): buffer +u is
    /// device −Y and buffer +v is device −X. A buffer pixel (u, v) shows at
    /// portrait (height − v, u).
    public static func portrait(
        fromLandscapeBuffer fx: Double, fy: Double, cx: Double, cy: Double, width: Double, height: Double
    ) -> CameraIntrinsics {
        CameraIntrinsics(fx: fy, fy: fx, cx: height - cy, cy: cx, width: height, height: width)
    }

    /// The same camera in the coordinates of a view that shows the image with
    /// aspect-fill (`AVLayerVideoGravity.resizeAspectFill`): scaled to cover
    /// the view and centred, the overflow cropped.
    public func aspectFilled(toWidth viewWidth: Double, height viewHeight: Double) -> CameraIntrinsics {
        let s = max(viewWidth / width, viewHeight / height)
        return CameraIntrinsics(
            fx: fx * s, fy: fy * s,
            cx: cx * s - (width * s - viewWidth) / 2,
            cy: cy * s - (height * s - viewHeight) / 2,
            width: viewWidth, height: viewHeight)
    }

    func contains(_ p: PixelPoint) -> Bool {
        (0...width).contains(p.u) && (0...height).contains(p.v)
    }
}

public enum SkyProjection: Sendable, Hashable {
    case inFrame(PixelPoint)
    /// In front of the camera but outside the image; the pixel is still valid
    /// for drawing an edge marker or a line that leaves the frame.
    case outsideFrame(PixelPoint)
    case behindCamera

    public var pixel: PixelPoint? {
        switch self {
        case .inFrame(let p), .outsideFrame(let p): p
        case .behindCamera: nil
        }
    }
}

/// Projects sky directions onto the camera image for one attitude and
/// intrinsics (frames in SkyFrames.swift). Positions should be apparent
/// (`Refraction.normal`), since that is where the camera sees them.
public struct SkyProjector: Sendable, Hashable {
    public let attitude: DeviceAttitude
    public let intrinsics: CameraIntrinsics

    /// Paths are clipped where the camera-frame z drops to this: 0.01 is
    /// 0.6° in front of the image plane, far outside any real frame.
    static let nearPlane = 0.01

    public init(attitude: DeviceAttitude, intrinsics: CameraIntrinsics) {
        self.attitude = attitude
        self.intrinsics = intrinsics
    }

    /// Camera-frame unit vector for a sky direction (frame 6).
    public func cameraVector(_ position: HorizontalPosition) -> SIMD3<Double> {
        let d = attitude.device(position)
        return SIMD3(d.x, -d.y, -d.z)
    }

    public func project(_ position: HorizontalPosition) -> SkyProjection {
        let c = cameraVector(position)
        guard c.z > 1e-9 else { return .behindCamera }
        let p = pixel(c)
        return intrinsics.contains(p) ? .inFrame(p) : .outsideFrame(p)
    }

    /// Sky direction seen at a pixel (the inverse of `project`).
    public func unproject(_ p: PixelPoint) -> HorizontalPosition {
        let c = SIMD3((p.u - intrinsics.cx) / intrinsics.fx, (p.v - intrinsics.cy) / intrinsics.fy, 1)
        return attitude.position(ofDevice: SIMD3(c.x, -c.y, -c.z))
    }

    /// Where the optical axis points.
    public var boresight: HorizontalPosition {
        unproject(PixelPoint(u: intrinsics.cx, v: intrinsics.cy))
    }

    /// Direction on screen from the principal point toward `position`, in
    /// radians (0 = +u/right, π/2 = +v/down), for an edge arrow when it is
    /// outside the frame or behind the camera. Nil only straight ahead or behind.
    public func screenDirection(toward position: HorizontalPosition) -> Double? {
        let c = cameraVector(position)
        let x = c.x * intrinsics.fx, y = c.y * intrinsics.fy
        guard x != 0 || y != 0 else { return nil }
        return atan2(y, x)
    }

    /// A sampled sky path (the Milky Way band, the GC's track) as drawable
    /// runs of pixels: split where it passes behind the camera and clipped
    /// at `nearPlane`, so no segment ever joins across the back of the camera.
    /// Runs may extend outside the frame; the view clips them.
    public func projectPath(_ positions: [HorizontalPosition], closed: Bool = false) -> [[PixelPoint]] {
        var vectors = positions.map(cameraVector)
        if closed, let first = vectors.first, vectors.count > 1 { vectors.append(first) }
        let near = Self.nearPlane
        var runs: [[PixelPoint]] = []
        var run: [PixelPoint] = []
        func endRun() {
            if run.count > 1 { runs.append(run) }
            run = []
        }
        for (i, c) in vectors.enumerated() {
            if i > 0 {
                let prev = vectors[i - 1]
                if (prev.z >= near) != (c.z >= near) {
                    let t = (near - prev.z) / (c.z - prev.z)
                    let crossing = pixel(prev + (c - prev) * t)
                    if prev.z >= near {
                        run.append(crossing)
                        endRun()
                    } else {
                        run = [crossing]
                    }
                }
            }
            if c.z >= near { run.append(pixel(c)) }
        }
        endRun()
        return runs
    }

    private func pixel(_ c: SIMD3<Double>) -> PixelPoint {
        PixelPoint(u: intrinsics.fx * c.x / c.z + intrinsics.cx, v: intrinsics.fy * c.y / c.z + intrinsics.cy)
    }
}
