public import Foundation

extension ShotTarget {
    /// Where the target stands at `date`, as the shot window reports it: the
    /// arch's midpoint, the Moon's top limb, refracted planets and fixed
    /// targets, the geometric core. The map draws its line along this azimuth.
    public func position(_ observer: Observer, at date: Date) throws(AstronomyError) -> HorizontalPosition {
        try placement(observer, at: date, threshold: { _ in 0 }).position
    }
}
