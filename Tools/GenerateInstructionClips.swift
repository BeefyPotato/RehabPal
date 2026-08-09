import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let clips = ["balance", "squeeze", "wristAssessment", "fingerROM"]
let width = 640
let height = 360
let fps: Int32 = 24
let duration = 6

func drawFrame(kind: String, progress: Double, into buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer),
          let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    context.setFillColor(CGColor(red: 0.05, green: 0.16, blue: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let wave = CGFloat(sin(progress * .pi * 2))
    context.setFillColor(CGColor(red: 0.22, green: 0.78, blue: 0.72, alpha: 1))
    if kind == "balance" {
        context.fill(CGRect(x: 110, y: 85, width: 420, height: 190))
        context.setFillColor(CGColor(gray: 0.08, alpha: 1)); context.fillEllipse(in: CGRect(x: 430, y: 155, width: 70, height: 70))
        context.setFillColor(CGColor(gray: 0.96, alpha: 1)); context.fillEllipse(in: CGRect(x: 285 + wave * 135, y: 165, width: 48, height: 48))
    } else {
        let palm = CGRect(x: 235, y: 80, width: 170, height: 150)
        context.fillEllipse(in: palm)
        for index in 0..<5 {
            let bend = (kind == "squeeze" || kind == "fingerROM") ? max(0, wave) * CGFloat(42 + index * 3) : wave * 18
            context.fill(CGRect(x: 238 + CGFloat(index) * 34, y: 210 - bend, width: 25, height: CGFloat(100 - index * 5)))
        }
        if kind == "squeeze" {
            context.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.18, alpha: 1)); context.fillEllipse(in: CGRect(x: 280, y: 115, width: 80, height: 80))
        }
    }
}

for kind in clips {
    let url = outputDirectory.appendingPathComponent("\(kind).mp4")
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    for frame in 0..<(duration * Int(fps)) {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        drawFrame(kind: kind, progress: Double(frame) / Double(duration * Int(fps)), into: buffer!)
        adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "ClipWriter", code: 1) }
}
