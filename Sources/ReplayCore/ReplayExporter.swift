import AVFoundation

public enum ReplayExporter {
  public static func save(_ snapshot: ReplaySnapshot, to url: URL) async throws {
    guard let format = snapshot.samples.first.flatMap(CMSampleBufferGetFormatDescription) else {
      throw ReplayError.empty
    }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
    input.expectsMediaDataInRealTime = false
    guard writer.canAdd(input) else {
      throw ReplayError.export("This video format cannot be saved as MP4.")
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? ReplayError.export("Couldn’t create the video file.")
    }
    // The edit list hides earlier frames while retaining the keyframe needed to decode them.
    writer.startSession(atSourceTime: snapshot.start)
    let job = ExportJob(writer: writer, input: input, snapshot: snapshot)
    defer { job.timeout?.cancel() }
    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        job.start(continuation)
      }
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }
}

private final class ExportJob {
  let writer: AVAssetWriter
  let input: AVAssetWriterInput
  let snapshot: ReplaySnapshot
  var continuation: CheckedContinuation<Void, Error>?
  let queue = DispatchQueue(label: "app.backtobug.export", qos: .userInitiated)
  var index = 0
  var finished = false
  var finishing = false
  var timeout: DispatchWorkItem?

  init(writer: AVAssetWriter, input: AVAssetWriterInput, snapshot: ReplaySnapshot) {
    self.writer = writer
    self.input = input
    self.snapshot = snapshot
  }

  func start(_ continuation: CheckedContinuation<Void, Error>) {
    self.continuation = continuation
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, !finished else { return }
      writer.cancelWriting()
      complete(
        .failure(
          ReplayError.export("Saving took too long. Check that the destination drive is available.")
        ))
    }
    self.timeout = timeout
    queue.asyncAfter(deadline: .now() + 120, execute: timeout)
    input.requestMediaDataWhenReady(on: queue) { [weak self] in
      guard let self, !finished && !finishing else { return }
      while input.isReadyForMoreMediaData && index < snapshot.samples.count {
        guard input.append(snapshot.samples[index]) else {
          writer.cancelWriting()
          complete(
            .failure(
              writer.error
                ?? ReplayError.export(
                  "Couldn’t write the video. Check the destination’s free space.")))
          return
        }
        index += 1
      }
      if index == snapshot.samples.count {
        finishing = true
        input.markAsFinished()
        writer.endSession(atSourceTime: snapshot.end)
        writer.finishWriting { [weak self] in
          guard let self else { return }
          self.queue.async { [weak self] in
            guard let self else { return }
            if self.writer.status == .completed {
              self.complete(.success(()))
            } else {
              self.complete(
                .failure(
                  self.writer.error ?? ReplayError.export("The video could not be finalized.")))
            }
          }
        }
      } else if writer.status == .failed {
        complete(.failure(writer.error ?? ReplayError.export("Saving the video failed.")))
      }
    }
  }

  func complete(_ result: Result<Void, Error>) {
    guard !finished else { return }
    finished = true
    timeout?.cancel()
    timeout = nil
    continuation?.resume(with: result)
    continuation = nil
  }
}
