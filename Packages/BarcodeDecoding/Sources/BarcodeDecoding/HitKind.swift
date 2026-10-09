/// What a scanline decoded: a whole symbol or one half of an EAN-13/EAN-8.
enum HitKind: Equatable {
    case full
    case leftHalf
    case rightHalf
}
