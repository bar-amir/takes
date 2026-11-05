// Encodes a folder of RGBA PNG frames into HEVC-with-alpha (.mov) with Apple's own encoder, for Safari on iOS and macOS.
// Usage: hevcalpha <frames-dir> <fps> <out.mov> [alphaQuality 0...1] [bitsPerPixel]
import AVFoundation
import AppKit
import CoreImage

let a = CommandLine.arguments
let dir = URL(fileURLWithPath: a[1]), fps = Int32(a[2])!, out = URL(fileURLWithPath: a[3])
let alphaQ = a.count > 4 ? Double(a[4])! : 0.9
let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.sorted()
guard let first = NSImage(contentsOf: dir.appendingPathComponent(files[0]))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("no frames") }
let w = first.width, h = first.height
try? FileManager.default.removeItem(at: out)
let writer = try AVAssetWriter(outputURL: out, fileType: .mov)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha, AVVideoWidthKey: w, AVVideoHeightKey: h,
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    AVVideoCompressionPropertiesKey: [kVTCompressionPropertyKey_TargetQualityForAlpha as String: alphaQ,
                                      AVVideoQualityKey: 0.7, AVVideoExpectedSourceFrameRateKey: fps],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
for (i, name) in files.enumerated() {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    guard let img = NSImage(contentsOf: dir.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let pool = adaptor.pixelBufferPool else { continue }
    var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb); guard let pb else { continue }
    CVPixelBufferLockBaseAddress(pb, [])
    // Premultiplied BGRA, cleared first so fully transparent pixels are exactly zero.
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h)); ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    CVPixelBufferUnlockBaseAddress(pb, [])
    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
print(writer.status == .completed ? "wrote \(files.count) frames to \(out.path)" : "failed: \(String(describing: writer.error))")
