import BarcodeDecoding
import Testing

struct BarcodeDecoderTests {
    private func decode(_ barcode: TestBarcode, rotated: Bool = false) -> [BarcodeReading] {
        let pixels = barcode.image(rotated: rotated)
        let size = barcode.size(rotated: rotated)
        return pixels.withUnsafeBufferPointer { buffer in
            let image = LumaImage(pixels: buffer.baseAddress!, width: size.width, height: size.height, bytesPerRow: size.width)
            let region = ScanRegion(minX: 0, minY: 0, maxX: size.width, maxY: size.height)
            return BarcodeDecoder().decode(image, region: region, options: .still(width: size.width, height: size.height))
        }
    }

    @Test(arguments: [false, true])
    func readsEAN13(rotated: Bool) throws {
        let reading = try #require(decode(.ean13("4006381333931"), rotated: rotated).first)
        #expect(reading.format == .ean13)
        #expect(reading.text == "4006381333931")
        #expect(reading.lineCount >= 2)
    }

    @Test func readsUPCAAsEAN13WithLeadingZero() throws {
        let reading = try #require(decode(.ean13("0036000291452")).first)
        #expect(reading.text == "0036000291452")
    }

    @Test(arguments: [false, true])
    func readsEAN8(rotated: Bool) throws {
        let reading = try #require(decode(.ean8("96385074"), rotated: rotated).first)
        #expect(reading.format == .ean8)
        #expect(reading.text == "96385074")
    }

    @Test(arguments: [false, true])
    func readsUPCE(rotated: Bool) throws {
        let reading = try #require(decode(.upcE("06543217"), rotated: rotated).first)
        #expect(reading.format == .upcE)
        #expect(reading.text == "06543217")
    }

    @Test func rejectsABrokenCheckDigit() {
        // 4006381333931 with its check digit changed.
        #expect(decode(.ean13("4006381333932")).isEmpty)
    }

    @Test func outlineSpansTheBars() throws {
        let barcode = TestBarcode.ean13("4006381333931")
        let reading = try #require(decode(barcode).first)
        // Drawn from x = 45 (15 quiet modules of 3 px) to 330, bars from y = 40 to 160.
        #expect(abs(reading.topLeft.x - 45) < 3)
        #expect(abs(reading.topRight.x - 330) < 3)
        #expect(abs(reading.topLeft.y - 40) < 6)
        #expect(abs(reading.bottomLeft.y - 160) < 6)
        #expect(abs(reading.moduleSize - 3) < 0.2)
    }
}
