import Foundation

extension UserDefaults {
    /// The Bool set for `key`, or nil when none is: unset isn't false. Like
    /// `bool(forKey:)`, it also reads `-key YES` launch arguments, which arrive
    /// as strings.
    nonisolated func optionalBool(forKey key: String) -> Bool? {
        object(forKey: key) == nil ? nil : bool(forKey: key)
    }
}
