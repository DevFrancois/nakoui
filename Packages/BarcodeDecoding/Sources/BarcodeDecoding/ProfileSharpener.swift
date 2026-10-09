/// A 3-tap unsharp mask for the passes over blurred lines: v' = 2 v - (v[-d] + v[+d]) / 2. It
/// pulls apart the edges of narrow elements that blur pushed together; `distance` follows the
/// blur width in samples. It also doubles the noise, so it only runs on lines that came close.
enum ProfileSharpener {
    static func sharpen(_ source: UnsafePointer<Int32>, count: Int, distance d: Int, into target: UnsafeMutablePointer<Int32>) {
        guard count > 2 * d else {
            for i in 0..<count { target[i] = source[i] }
            return
        }
        for i in 0..<d { target[i] = source[i] }
        for i in d..<(count - d) {
            target[i] = 2 &* source[i] &- (source[i &- d] &+ source[i &+ d]) / 2
        }
        for i in (count - d)..<count { target[i] = source[i] }
    }
}
