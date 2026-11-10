import ReplayCore
import ScreenCaptureKit

// Encoder state belongs to the capture queue; stream lifecycle belongs to the main actor.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  let buffer: ReplayBuffer
  private let onFailure: @Sendable (Error) -> Void
  private let queue = DispatchQueue(label: "app.backtobug.capture", qos: .userInitiated)
  @MainActor private var stream: SCStream?
  @MainActor private var stopped = false
  private var encoder: VideoEncoder?
  private var timer: DispatchSourceTimer?
  private var image: CVPixelBuffer?
  private var failed = false

  init(duration: Int, onFailure: @escaping @Sendable (Error) -> Void) {
    buffer = ReplayBuffer(duration: Double(duration))
    self.onFailure = onFailure
    super.init()
  }

  @MainActor func start(
    display: SCDisplay, applications: [SCRunningApplication], settings: AppSettings
  ) async throws {
    let filter = SCContentFilter(
      display: display, excludingApplications: applications, exceptingWindows: [])
    let nativeWidth = filter.contentRect.width * CGFloat(filter.pointPixelScale)
    let nativeHeight = filter.contentRect.height * CGFloat(filter.pointPixelScale)
    let scale = min(1, CGFloat(settings.quality.maximumDimension) / max(nativeWidth, nativeHeight))
    let width = max(2, Int(nativeWidth * scale) / 2 * 2)
    let height = max(2, Int(nativeHeight * scale) / 2 * 2)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async { [self] in
        do {
          encoder = try VideoEncoder(
            width: width, height: height, fps: settings.fps, bitrate: settings.quality.bitrate
          ) { [weak self] result in
            switch result {
            case .success(let sample): self?.buffer.append(sample)
            case .failure(let error): self?.onFailure(error)
            }
          }
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
    guard !stopped else { throw CancellationError() }
    let configuration = SCStreamConfiguration()
    configuration.width = width
    configuration.height = height
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(settings.fps))
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.queueDepth = 3
    configuration.showsCursor = settings.showsCursor
    if #available(macOS 15, *) { configuration.showMouseClicks = settings.showsClicks }
    configuration.capturesAudio = false
    configuration.colorSpaceName = CGColorSpace.sRGB
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    self.stream = stream
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
    guard !stopped else {
      try? await stream.stopCapture()
      throw CancellationError()
    }
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        guard !failed else {
          continuation.resume()
          return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
          deadline: .now(), repeating: .nanoseconds(1_000_000_000 / settings.fps),
          leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.encodeLatestFrame() }
        self.timer = timer
        timer.resume()
        continuation.resume()
      }
    }
  }

  private func encodeLatestFrame() {
    guard !failed, let image else { return }
    do { try encoder?.encode(image, at: CMClockGetTime(CMClockGetHostTimeClock())) } catch {
      failed = true
      onFailure(error)
    }
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    guard type == .screen,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
        as? [[SCStreamFrameInfo: Any]],
      let rawStatus = attachments.first?[.status] as? Int,
      let status = SCFrameStatus(rawValue: rawStatus)
    else { return }
    if status == .complete, let surface = CMSampleBufferGetImageBuffer(sample) {
      image = surface
    } else if status == .blank || status == .suspended || status == .stopped, image != nil {
      image = nil
      do { try encoder?.beginNewSequence() } catch { onFailure(error) }
      buffer.reset()
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure(error) }

  func snapshot() async throws -> ReplaySnapshot {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          try encoder?.flush()
          continuation.resume(returning: try buffer.snapshot())
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  @MainActor func stop() async {
    stopped = true
    let stream = self.stream
    self.stream = nil
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        timer?.cancel()
        timer = nil
        image = nil
        failed = true
        encoder?.invalidate()
        encoder = nil
        buffer.reset()
        continuation.resume()
      }
    }
    try? await stream?.stopCapture()
  }
}
