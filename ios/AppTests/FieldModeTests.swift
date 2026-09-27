import Foundation
import Testing
@testable import DarkSky

/// Field-mode persistence and the brightness rules, without a screen.
@MainActor
struct FieldModeTests {
    private func defaults() -> UserDefaults {
        let name = "FieldModeTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func fieldModeIsRememberedAcrossLaunches() {
        let d = defaults()
        #expect(FieldModePreference.initial(d) == false)
        FieldModePreference.save(true, d, arguments: [])
        #expect(FieldModePreference.initial(d) == true)
        FieldModePreference.save(false, d, arguments: [])
        #expect(FieldModePreference.initial(d) == false)
    }

    @Test func launchArgumentIsNeverWrittenBack() {
        let d = defaults()
        FieldModePreference.save(true, d, arguments: ["-FieldMode", "YES"])
        #expect(d.object(forKey: FieldModePreference.key) == nil)
    }

    @Test func nothingChangesUntilTheOwnerMovesTheControl() {
        var s = BrightnessSession()
        #expect(s.activate(system: 0.8) == nil)
        #expect(s.release() == nil)
    }

    @Test func firstChangeRemembersAndReleaseRestoresTheSystemLevel() {
        var s = BrightnessSession()
        #expect(s.set(0.05, system: 0.8) == 0.05)
        #expect(s.set(0.1, system: 0.05) == 0.1, "a second change keeps the original system level")
        #expect(s.release() == 0.8)
        #expect(s.release() == nil, "restores once")
    }

    @Test func returningToFieldModeReappliesTheChosenLevel() {
        var s = BrightnessSession()
        _ = s.set(0.2, system: 0.7)
        #expect(s.release() == 0.7)
        #expect(s.activate(system: 0.6) == 0.2)
        #expect(s.release() == 0.6)
    }

    @Test func levelsAreClamped() {
        var s = BrightnessSession()
        #expect(s.set(-1, system: 0.5) == 0)
        #expect(s.set(3, system: 0.5) == 1)
    }

    /// A process killed while holding the screen restores on the next launch.
    @Test func persistedSessionRestoresAfterAKill() throws {
        let d = defaults()
        final class Box { var brightness: CGFloat = 0.9 }
        let box = Box()
        let screen = FakeScreen(box: { box.brightness }, set: { box.brightness = $0 })
        let first = FieldBrightness(defaults: d, screenBrightness: screen)
        first.sync(fieldMode: true, active: true)
        first.set(0.1)
        #expect(box.brightness == 0.1)
        // Killed here: no release. Next launch, field mode off.
        let second = FieldBrightness(defaults: d, screenBrightness: screen)
        second.sync(fieldMode: false, active: true)
        #expect(abs(box.brightness - 0.9) < 1e-9)
        // And next launch in field mode keeps the original level to give back.
        let third = FieldBrightness(defaults: d, screenBrightness: screen)
        third.set(0.2)
        third.sync(fieldMode: true, active: false)
        #expect(abs(box.brightness - 0.9) < 1e-9)
    }
}

struct FakeScreen: ScreenBrightness {
    let box: () -> CGFloat
    let set: (CGFloat) -> Void
    var brightness: CGFloat {
        get { box() }
        nonmutating set { set(newValue) }
    }
}
