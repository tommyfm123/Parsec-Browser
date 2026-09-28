import AppKit
import CoreImage

let logoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[2])
let markOutputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let iconSizes = [16, 32, 64, 128, 256, 512]
let tileInsetRatio: CGFloat = 100 / 1024
let tileCornerRatio: CGFloat = 185 / 1024
let markScale: CGFloat = 0.6

func makeMarkImage(from url: URL) -> CGImage {
    let source = CIImage(contentsOf: url)!
    let noiseCut = CIVector(x: 1.3, y: 0, z: 0, w: 0)
    let inverted = source.applyingFilter("CIColorInvert").applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": noiseCut, "inputGVector": CIVector(x: 0, y: 1.3, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1.3, w: 0),
        "inputBiasVector": CIVector(x: -0.3, y: -0.3, z: -0.3, w: 0),
    ])
    let alphaMask = inverted.applyingFilter("CIMaskToAlpha")
    let white = CIImage(color: .white).cropped(to: source.extent)
    let mark = white.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputMaskImageKey: alphaMask, kCIInputBackgroundImageKey: CIImage.empty()])
    let fullImage = CIContext().createCGImage(mark, from: source.extent)!
    return fullImage.cropping(to: opaqueBounds(of: fullImage))!
}

func opaqueBounds(of image: CGImage) -> CGRect {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = 0, maxY = 0
    for row in 0..<height {
        for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 24 {
            minX = min(minX, column); maxX = max(maxX, column)
            minY = min(minY, row); maxY = max(maxY, row)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let markImage = makeMarkImage(from: logoURL)
let markBitmap = NSBitmapImageRep(cgImage: markImage)
try markBitmap.representation(using: .png, properties: [:])!.write(to: markOutputURL)

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let side = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let inset = side * tileInsetRatio
    let tileRect = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: side * tileCornerRatio, yRadius: side * tileCornerRatio)
    NSGradient(colors: [
        NSColor(white: 1, alpha: 1),
        NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1),
    ])!.draw(in: tile, angle: -90)
    NSColor.black.withAlphaComponent(0.08).setStroke()
    tile.lineWidth = max(side / 512, 0.5)
    tile.stroke()
    let markWidth = tileRect.width * markScale
    let markHeight = markWidth * CGFloat(markImage.height) / CGFloat(markImage.width)
    let markRect = NSRect(x: tileRect.midX - markWidth / 2, y: tileRect.midY - markHeight / 2, width: markWidth, height: markHeight)
    NSGraphicsContext.current?.saveGraphicsState()
    let markContext = NSGraphicsContext.current!.cgContext
    markContext.clip(to: markRect, mask: markImage)
    NSColor(white: 0.04, alpha: 1).setFill()
    markRect.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
for size in iconSizes {
    try drawIcon(pixels: size).representation(using: .png, properties: [:])!.write(to: iconsetURL.appending(path: "icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).representation(using: .png, properties: [:])!.write(to: iconsetURL.appending(path: "icon_\(size)x\(size)@2x.png"))
}
