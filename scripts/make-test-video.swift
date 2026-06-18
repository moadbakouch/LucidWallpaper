#!/usr/bin/env swift
// Generates a short looping H.264 .mp4 test pattern (no ffmpeg needed).
// Usage: swift scripts/make-test-video.swift /tmp/test.mp4
import AVFoundation
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/lucidwallpaper-test.mp4"
let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: outURL)

let W = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 640) : 640
let H = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 360) : 360
let fps: Int32 = 30
let total = Int(fps) * 4   // 4 seconds

let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W,
    AVVideoHeightKey: H,
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H,
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let sem = DispatchSemaphore(value: 0)
var frame = 0
input.requestMediaDataWhenReady(on: DispatchQueue(label: "gen")) {
    while input.isReadyForMoreMediaData && frame < total {
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        guard let buf = pb else { break }
        CVPixelBufferLockBaseAddress(buf, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                            width: W, height: H, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let t = CGFloat(frame) / CGFloat(total)
        ctx.setFillColor(NSColor(hue: t, saturation: 0.7, brightness: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        let cx = CGFloat(W) * (0.5 + 0.4 * sin(t * .pi * 2))
        let cy = CGFloat(H) * (0.5 + 0.3 * cos(t * .pi * 2))
        ctx.fillEllipse(in: CGRect(x: cx - 28, y: cy - 28, width: 56, height: 56))
        CVPixelBufferUnlockBaseAddress(buf, [])
        adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        frame += 1
    }
    if frame >= total {
        input.markAsFinished()
        writer.finishWriting { sem.signal() }
    }
}
sem.wait()
print("wrote \(outURL.path) (status=\(writer.status.rawValue), frames=\(frame))")
