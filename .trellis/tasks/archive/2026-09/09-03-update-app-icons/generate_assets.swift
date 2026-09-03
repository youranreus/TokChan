import CoreGraphics
import Foundation
import ImageIO

private let repositoryURL = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath,
    isDirectory: true
)
private let sourceDirectoryURL = repositoryURL
    .appendingPathComponent("BrandAssets/Sources", isDirectory: true)
private let opaqueLogoURL = sourceDirectoryURL.appendingPathComponent("TokChan_Logo.png")
private let transparentLogoURL = sourceDirectoryURL.appendingPathComponent("TokChan_transparent.png")
private let catalogURL = repositoryURL
    .appendingPathComponent("TokChan/Assets.xcassets", isDirectory: true)
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private struct PixelBounds {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

private func loadImage(at url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
    }
    return image
}

private func makeContext(width: Int, height: Int) throws -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw CocoaError(.coderInvalidValue)
    }
    context.interpolationQuality = .high
    return context
}

private func normalizedImage(_ image: CGImage) throws -> CGImage {
    let context = try makeContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return result
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
    ) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationEmbedThumbnail: false,
        kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
        kCGImagePropertyProfileName: "sRGB"
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
    }
}

private func alphaBounds(of image: CGImage, minimumAlpha: UInt8 = 0) throws -> PixelBounds {
    let context = try makeContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { throw CocoaError(.coderInvalidValue) }
    let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)

    var minX = image.width
    var minY = image.height
    var maxX = -1
    var maxY = -1
    for y in 0..<image.height {
        for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > minimumAlpha {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { throw CocoaError(.coderInvalidValue) }
    return PixelBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
}

private func makeAppIconMaster(from source: CGImage) throws -> CGImage {
    let size = 1024
    let context = try makeContext(width: size, height: size)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.addPath(CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: 184,
        cornerHeight: 184,
        transform: nil
    ))
    context.clip()

    let scale = min(CGFloat(size) / CGFloat(source.width), CGFloat(size) / CGFloat(source.height))
    let drawWidth = CGFloat(source.width) * scale
    let drawHeight = CGFloat(source.height) * scale
    context.draw(source, in: CGRect(
        x: (CGFloat(size) - drawWidth) / 2,
        y: (CGFloat(size) - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    ))
    guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return result
}

private func resize(_ source: CGImage, to size: Int) throws -> CGImage {
    let context = try makeContext(width: size, height: size)
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return result
}

private func makeMenuBarIcon(from source: CGImage, size: Int) throws -> CGImage {
    let context = try makeContext(width: size, height: size)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let contentSize = CGFloat(size) * 16 / 18
    let scale = min(contentSize / CGFloat(source.width), contentSize / CGFloat(source.height))
    let drawWidth = CGFloat(source.width) * scale
    let drawHeight = CGFloat(source.height) * scale
    context.draw(source, in: CGRect(
        x: (CGFloat(size) - drawWidth) / 2,
        y: (CGFloat(size) - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    ))

    guard let data = context.data else { throw CocoaError(.coderInvalidValue) }
    let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
    for index in 0..<(size * size) {
        pixels[index * 4] = 0
        pixels[index * 4 + 1] = 0
        pixels[index * 4 + 2] = 0
    }
    guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return result
}

private func makeAboutLogo(from source: CGImage, bounds: PixelBounds) throws -> CGImage {
    let context = try makeContext(width: bounds.width, height: bounds.height)
    context.clear(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
    context.draw(source, in: CGRect(
        x: -bounds.minX,
        y: bounds.height - source.height + bounds.minY,
        width: source.width,
        height: source.height
    ))
    guard let result = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return result
}

private let opaqueLogo = try normalizedImage(loadImage(at: opaqueLogoURL))
private let transparentLogo = try normalizedImage(loadImage(at: transparentLogoURL))
private let transparentBounds = try alphaBounds(of: transparentLogo, minimumAlpha: 2)

private let appIconDirectory = catalogURL.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
private let appIconMaster = try makeAppIconMaster(from: opaqueLogo)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try writePNG(try resize(appIconMaster, to: size), to: appIconDirectory.appendingPathComponent("AppIcon-\(size).png"))
}

private let aboutLogo = try makeAboutLogo(from: transparentLogo, bounds: transparentBounds)
try writePNG(aboutLogo, to: catalogURL.appendingPathComponent("AboutLogo.imageset/AboutLogo.png"))

private let menuBarDirectory = catalogURL.appendingPathComponent("MenuBarIcon.imageset", isDirectory: true)
for size in [18, 36] {
    try writePNG(
        try makeMenuBarIcon(from: aboutLogo, size: size),
        to: menuBarDirectory.appendingPathComponent("MenuBarIcon-\(size).png")
    )
}

print("Generated assets from alpha bounds x=\(transparentBounds.minX)...\(transparentBounds.maxX), y=\(transparentBounds.minY)...\(transparentBounds.maxY) (\(transparentBounds.width)x\(transparentBounds.height))")
