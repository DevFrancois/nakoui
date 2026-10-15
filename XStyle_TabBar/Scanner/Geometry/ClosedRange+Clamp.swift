nonisolated extension ClosedRange {
    /// `value`, moved inside the range if it falls outside.
    func clamp(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
