import ImageIO
import Metal
import UIKit

/// Decodes image inputs once. Layout and motion updates never touch this cache.
final class CarouselTextureStore {
    private static let maximumImageDimension = 4096
    private static let uploadBatchLimit = 32 * 1024 * 1024
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var cache: [String: MTLTexture] = [:]
    private(set) var images: [String] = []
    private(set) var textures: [MTLTexture] = []
    private let placeholder: MTLTexture

    init?(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.queue = queue
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let neutral = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel: [UInt8] = [192, 192, 192, 255]
        pixel.withUnsafeMutableBytes {
            neutral.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        neutral.label = "Carousel missing image"
        placeholder = neutral
    }

    /// `rendered` supplies pictures drawn from card views; they replace any cached
    /// texture for their input, so a re-render at a new size takes effect.
    func setImages(_ inputs: [String], rendered: [String: CGImage] = [:]) {
        guard inputs != images || !rendered.isEmpty else { return }
        images = inputs
        var command: MTLCommandBuffer?
        var blit: MTLBlitCommandEncoder?
        var uploadedBytes = 0
        func commitUploads() {
            blit?.endEncoding()
            command?.commit()
            blit = nil
            command = nil
            uploadedBytes = 0
        }
        textures = inputs.map { input in
            if rendered[input] == nil, let texture = cache[input] { return texture }
            // Decode temporaries are released per image; committed Metal 3 command
            // buffers retain staging resources until their GPU uploads finish.
            let texture = autoreleasepool { () -> MTLTexture in
                guard let image = rendered[input] ?? load(input) else { return placeholder }
                let imageBytes = ((image.width * 4 + 255) / 256) * 256 * image.height
                if uploadedBytes > 0 && imageBytes > Self.uploadBatchLimit - uploadedBytes {
                    commitUploads()
                }
                if blit == nil {
                    command = queue.makeCommandBuffer()
                    command?.label = "Carousel image uploads"
                    blit = command?.makeBlitCommandEncoder()
                }
                guard let blit,
                      let uploaded = makeTexture(image, blit: blit) else { return placeholder }
                uploadedBytes += uploaded.bytes
                return uploaded.texture
            }
            cache[input] = texture
            // Bound decoded staging memory per submission without blocking the CPU
            // on GPU completion. All later draws use this same ordered queue.
            if uploadedBytes >= Self.uploadBatchLimit { commitUploads() }
            return texture
        }
        commitUploads()
        // Retain shared inputs while allowing replaced image resources to be released.
        let retained = Set(inputs)
        cache = cache.filter { retained.contains($0.key) }
    }

    /// A picture outside the image list (a 3D card's back), uploaded on its own.
    func texture(from image: CGImage, label: String) -> MTLTexture? {
        guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else { return nil }
        command.label = "Carousel picture upload"
        let made = makeTexture(image, blit: blit)
        blit.endEncoding()
        command.commit()
        made?.texture.label = label
        return made?.texture
    }

    private func load(_ input: String) -> CGImage? {
        guard !input.isEmpty else { return nil }
        let image: CGImage?
        if input.hasPrefix("data:image/") {
            guard let comma = input.firstIndex(of: ",") else { return nil }
            let metadata = input[..<comma]
            let payload = String(input[input.index(after: comma)...])
            let data: Data?
            if metadata.hasSuffix(";base64") {
                data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            } else {
                data = decodePercentBytes(payload)
            }
            image = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap(decode)
        } else if let url = localURL(input),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            image = decode(source)
        } else if let asset = UIImage(named: input) {
            image = orientedImage(asset)
        } else {
            image = nil
        }
        return image
    }

    private func localURL(_ input: String) -> URL? {
        if input.hasPrefix("file:"), let url = URL(string: input), url.isFileURL { return url }
        if input.hasPrefix("/") { return URL(fileURLWithPath: input) }
        let path = input as NSString
        if let bundled = Bundle.main.url(forResource: path.deletingPathExtension,
                                         withExtension: path.pathExtension.isEmpty ? nil : path.pathExtension) {
            return bundled
        }
        guard let root = Bundle.main.resourceURL else { return nil }
        let candidate = root.appendingPathComponent(input)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func decode(_ source: CGImageSource) -> CGImage? {
        // ImageIO applies EXIF orientation while decoding; no encoded image is generated.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumImageDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func orientedImage(_ image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let largestSide = max(cgImage.width, cgImage.height)
        guard image.imageOrientation != .up || largestSide > Self.maximumImageDimension else { return cgImage }
        let sideways = [.left, .leftMirrored, .right, .rightMirrored].contains(image.imageOrientation)
        let scale = min(1, CGFloat(Self.maximumImageDimension) / CGFloat(largestSide))
        let size = CGSize(width: CGFloat(sideways ? cgImage.height : cgImage.width) * scale,
                          height: CGFloat(sideways ? cgImage.width : cgImage.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private func makeTexture(_ image: CGImage, blit: MTLBlitCommandEncoder) -> (texture: MTLTexture, bytes: Int)? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              width <= Self.maximumImageDimension, height <= Self.maximumImageDimension,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // A padded row pitch works across iOS GPUs and the Simulator's Metal
        // backend. Draw directly into upload memory instead of copying an array.
        let stride = ((width * 4 + 255) / 256) * 256
        let byteCount = stride * height
        guard let staging = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let context = CGContext(data: staging.contents(), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: stride, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        staging.label = "Carousel image staging"
        // Copy avoids reading/blending with uninitialized staging contents.
        context.setBlendMode(.copy)
        // CGImage and Metal UVs both start at the first decoded row.
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // Core Graphics premultiplies encoded sRGB. Metal blends in linear light,
        // so store encoded linear-premultiplied RGB for correct translucent edges.
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            break // Opaque photographs need neither a pixel scan nor conversion.
        default:
            let pixels = staging.contents().assumingMemoryBound(to: UInt8.self)
            let conversion = Self.linearPremultipliedSRGB
            for row in 0..<height {
                for offset in Swift.stride(from: row * stride, to: row * stride + width * 4, by: 4) {
                    let alpha = Int(pixels[offset + 3])
                    guard alpha > 0, alpha < 255 else { continue }
                    let tableOffset = alpha * 256
                    pixels[offset] = conversion[tableOffset + Int(pixels[offset])]
                    pixels[offset + 1] = conversion[tableOffset + Int(pixels[offset + 1])]
                    pixels[offset + 2] = conversion[tableOffset + Int(pixels[offset + 2])]
                }
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: stride,
                  sourceBytesPerImage: byteCount, sourceSize: MTLSizeMake(width, height, 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOriginMake(0, 0, 0))
        if texture.mipmapLevelCount > 1 { blit.generateMipmaps(for: texture) }
        texture.label = "Carousel image"
        return (texture, byteCount)
    }

    // 64 KiB, initialized only for an image with alpha. Equivalent to the sRGB
    // transfer functions above, without three pow() pairs per translucent pixel.
    private static let linearPremultipliedSRGB: [UInt8] = (0..<(256 * 256)).map { entry in
        let alphaByte = entry / 256
        let channelByte = entry % 256
        guard alphaByte > 0 else { return 0 }
        guard alphaByte < 255 else { return UInt8(channelByte) }
        let alpha = Double(alphaByte) / 255
        let encoded = min(1, Double(channelByte) / Double(alphaByte))
        let linear = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        let premultiplied = linear * alpha
        let stored = premultiplied <= 0.0031308 ? premultiplied * 12.92 : 1.055 * pow(premultiplied, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, (stored * 255).rounded())))
    }

    private func decodePercentBytes(_ value: String) -> Data? {
        let bytes = Array(value.utf8)
        var decoded = [UInt8]()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count,
                      let byte = UInt8(String(bytes: bytes[(index + 1)...(index + 2)], encoding: .utf8) ?? "", radix: 16) else { return nil }
                decoded.append(byte)
                index += 3
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        return Data(decoded)
    }
}
