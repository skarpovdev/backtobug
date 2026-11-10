import AVFoundation
import VideoToolbox
import XCTest

@testable import ReplayCore

final class ReplayCoreTests: XCTestCase {
  func testRollingWindowKeepsItsDecodingKeyframe() throws {
    let buffer = ReplayBuffer(duration: 2.5)
    for index in 0..<120 { buffer.append(try sample(index: index, keyframe: index % 30 == 0)) }
    let snapshot = try buffer.snapshot()
    XCTAssertEqual(snapshot.duration, 2.5, accuracy: 0.001)
    XCTAssertEqual(
      CMTimeGetSeconds(snapshot.samples[0].presentationTimeStamp), 101, accuracy: 0.001)
    XCTAssertEqual(CMTimeGetSeconds(snapshot.start), 101.5, accuracy: 0.001)
    XCTAssertEqual(buffer.statistics.duration, 2.5, accuracy: 0.001)
  }

  func testMemoryPressureDropsWholeDecodableGroups() throws {
    let buffer = ReplayBuffer(duration: 60, byteLimit: 45 * 16)
    for index in 0..<120 { buffer.append(try sample(index: index, keyframe: index % 30 == 0)) }
    let snapshot = try buffer.snapshot()
    XCTAssertLessThanOrEqual(buffer.statistics.bytes, 45 * 16)
    XCTAssertEqual(
      CMTimeGetSeconds(snapshot.samples[0].presentationTimeStamp), 103, accuracy: 0.001)
    XCTAssertEqual(snapshot.duration, 1, accuracy: 0.001)
  }

  func testOversizedGroupWaitsForNextKeyframe() throws {
    let buffer = ReplayBuffer(duration: 60, byteLimit: 32)
    buffer.append(try sample(index: 0, keyframe: true))
    buffer.append(try sample(index: 1, keyframe: false))
    buffer.append(try sample(index: 2, keyframe: false))
    buffer.append(try sample(index: 3, keyframe: false))
    XCTAssertThrowsError(try buffer.snapshot())
    buffer.append(try sample(index: 30, keyframe: true))
    XCTAssertEqual(try buffer.snapshot().samples.count, 1)
  }

  func testResetClearsHistoryWithoutChangingAnExistingSave() throws {
    let buffer = ReplayBuffer(duration: 60)
    buffer.append(try sample(index: 0, keyframe: true))
    let saving = try buffer.snapshot()
    buffer.reset()
    buffer.append(try sample(index: 1, keyframe: false))
    XCTAssertThrowsError(try buffer.snapshot())
    XCTAssertEqual(saving.samples.count, 1)
    XCTAssertEqual(buffer.statistics.bytes, 0)
    buffer.append(try sample(index: 30, keyframe: true))
    XCTAssertEqual(try buffer.snapshot().samples.count, 1)
  }

  func testEncodedReplayExportsAndDecodesFromInsideAKeyframeGroup() async throws {
    let buffer = ReplayBuffer(duration: 2.5)
    let encoder = try VideoEncoder(width: 320, height: 180, fps: 30, bitrate: 500_000) { result in
      if case .success(let sample) = result { buffer.append(sample) }
    }
    let image = try pixelBuffer()
    for index in 0..<120 {
      CVPixelBufferLockBaseAddress(image, [])
      if let address = CVPixelBufferGetBaseAddress(image) {
        memset(address, Int32(index % 255), CVPixelBufferGetDataSize(image))
      }
      CVPixelBufferUnlockBaseAddress(image, [])
      try encoder.encode(image, at: CMTime(value: Int64(3_000 + index), timescale: 30))
      try encoder.flush()
    }
    let snapshot = try buffer.snapshot()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("replay.mp4")
    defer { try? FileManager.default.removeItem(at: directory) }
    try await ReplayExporter.save(snapshot, to: url)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path), ["replay.mp4"])
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(CMTimeGetSeconds(duration), 2.5, accuracy: 0.04)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    XCTAssertTrue(reader.startReading())
    var frames = 0
    while let sample = output.copyNextSampleBuffer() {
      XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
      frames += 1
    }
    XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
    XCTAssertGreaterThanOrEqual(frames, 74)
  }

  func testFailedExportDoesNotReplaceAnExistingFile() async throws {
    let buffer = ReplayBuffer(duration: 2)
    buffer.append(try sample(index: 0, keyframe: true))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    let existing = Data("existing replay".utf8)
    try existing.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    do {
      try await ReplayExporter.save(buffer.snapshot(), to: url)
      XCTFail("An existing replay must not be overwritten")
    } catch { XCTAssertEqual(try Data(contentsOf: url), existing) }
  }

  private func sample(index: Int, keyframe: Bool) throws -> CMSampleBuffer {
    var block: CMBlockBuffer?
    XCTAssertEqual(
      CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 16,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
        offsetToData: 0, dataLength: 16, flags: 0, blockBufferOut: &block), noErr)
    var format: CMVideoFormatDescription?
    XCTAssertEqual(
      CMVideoFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
        width: 320, height: 180, extensions: nil, formatDescriptionOut: &format), noErr)
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: CMTime(value: Int64(3_000 + index), timescale: 30),
      decodeTimeStamp: .invalid)
    var size = 16
    var sample: CMSampleBuffer?
    XCTAssertEqual(
      CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
        sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample), noErr)
    let result = try XCTUnwrap(sample)
    let attachments =
      CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true)! as NSArray
    let attachment = attachments[0] as! NSMutableDictionary
    attachment[kCMSampleAttachmentKey_NotSync] = !keyframe
    return result
  }

  private func pixelBuffer() throws -> CVPixelBuffer {
    var image: CVPixelBuffer?
    XCTAssertEqual(
      CVPixelBufferCreate(
        kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image), kCVReturnSuccess)
    return try XCTUnwrap(image)
  }
}
