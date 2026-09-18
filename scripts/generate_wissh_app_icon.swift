#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = repositoryRoot.appendingPathComponent(
    "WisshApp/AppIcon/wissh-icon.svg"
)
let outputURL = repositoryRoot.appendingPathComponent(
    "WisshApp/Assets.xcassets/AppIcon.appiconset"
)

try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to decode the Wissh app icon SVG.\n", stderr)
    exit(1)
}

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    throw CocoaError(.coderInvalidValue)
}

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
source.draw(
    in: CGRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .copy,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL.appendingPathComponent("AppIcon-1024.png") as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      ) else {
    throw CocoaError(.fileWriteUnknown)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    throw CocoaError(.fileWriteUnknown)
}

let contents = """
{
  "images": [
    {
      "filename": "AppIcon-1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""
try contents.write(
    to: outputURL.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
