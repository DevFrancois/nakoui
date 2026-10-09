/// The four directions scanlines run in.
enum ScanFamily: Int {
    /// Down an image column (+y): bars along the buffer's x axis.
    case columns = 0
    /// Along an image row (+x).
    case rows = 1
    /// Along +x+y.
    case diagonal = 2
    /// Along +x-y.
    case antiDiagonal = 3
}
