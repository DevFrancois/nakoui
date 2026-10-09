import Foundation

/// One tile's part in the celebration wave: a hop, a wag and a squash.
/// Nonisolated because keyframe animations read it off the main actor.
nonisolated struct WordWagHop {
    var lift = 0.0
    /// In degrees.
    var tilt = 0.0
    var scale = 1.0
}
