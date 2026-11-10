import VideoToolbox

public final class VideoEncoder {
  private var session: VTCompressionSession?
  private let output: (Result<CMSampleBuffer, Error>) -> Void
  private let frameDuration: CMTime
  private var needsKeyframe = true

  public init(
    width: Int, height: Int, fps: Int, bitrate: Int,
    output: @escaping (Result<CMSampleBuffer, Error>) -> Void
  ) throws {
    self.output = output
    frameDuration = CMTime(value: 1, timescale: Int32(fps))
    let status = VTCompressionSessionCreate(
      allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
      codecType: kCMVideoCodecType_H264,
      encoderSpecification: [
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
      ] as CFDictionary,
      imageBufferAttributes: nil, compressedDataAllocator: nil,
      outputCallback: { context, _, status, _, sample in
        guard let context else { return }
        let encoder = Unmanaged<VideoEncoder>.fromOpaque(context).takeUnretainedValue()
        if status != noErr {
          encoder.output(.failure(ReplayError.encoding(status)))
        } else if let sample {
          encoder.output(.success(sample))
        }
      }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session
    )
    guard status == noErr, let session else { throw ReplayError.encoding(status) }
    do {
      try set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
      try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
      try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
      try set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
      try set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
      try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, fps as CFNumber)
      try set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 1 as CFNumber)
      let prepared = VTCompressionSessionPrepareToEncodeFrames(session)
      guard prepared == noErr else { throw ReplayError.encoding(prepared) }
    } catch {
      invalidate()
      throw error
    }
  }

  private func set(_ key: CFString, _ value: CFTypeRef) throws {
    guard let session else { return }
    let status = VTSessionSetProperty(session, key: key, value: value)
    guard status == noErr else { throw ReplayError.encoding(status) }
  }

  public func encode(_ image: CVPixelBuffer, at time: CMTime) throws {
    guard let session else { throw ReplayError.encoding(kVTInvalidSessionErr) }
    let properties =
      needsKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
    let status = VTCompressionSessionEncodeFrame(
      session, imageBuffer: image, presentationTimeStamp: time,
      duration: frameDuration, frameProperties: properties,
      sourceFrameRefcon: nil, infoFlagsOut: nil)
    guard status == noErr else { throw ReplayError.encoding(status) }
    needsKeyframe = false
  }

  public func flush() throws {
    guard let session else { return }
    let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    guard status == noErr else { throw ReplayError.encoding(status) }
  }

  public func beginNewSequence() throws {
    try flush()
    needsKeyframe = true
  }

  public func invalidate() {
    if let session { VTCompressionSessionInvalidate(session) }
    session = nil
  }

  deinit { invalidate() }
}
