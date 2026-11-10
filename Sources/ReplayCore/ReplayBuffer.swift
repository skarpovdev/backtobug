import AVFoundation

public enum ReplayError: LocalizedError {
  case empty
  case encoding(OSStatus)
  case export(String)

  public var errorDescription: String? {
    switch self {
    case .empty: return "There’s no video in the buffer yet. Wait a moment and try again."
    case .encoding(let code): return "The video encoder stopped (\(code)). Try resuming recording."
    case .export(let message): return message
    }
  }
}

public struct ReplaySnapshot {
  public let samples: [CMSampleBuffer]
  public let start: CMTime
  public let end: CMTime
  public var duration: Double { CMTimeGetSeconds(end - start) }
}

public struct BufferStatistics {
  public let duration: Double
  public let bytes: Int
}

public final class ReplayBuffer {
  private struct Group {
    var samples: [CMSampleBuffer]
    let start: CMTime
    var bytes: Int
  }

  private let lock = NSLock()
  private let duration: Double
  private let byteLimit: Int
  private var groups: [Group] = []
  private var bytes = 0
  private var end = CMTime.zero

  public init(duration: Double, byteLimit: Int = 512 * 1_024 * 1_024) {
    self.duration = max(1, duration)
    self.byteLimit = max(1, byteLimit)
  }

  public func append(_ sample: CMSampleBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard CMSampleBufferDataIsReady(sample) else { return }
    let time = CMSampleBufferGetPresentationTimeStamp(sample)
    guard time.isNumeric else { return }
    let attachments =
      CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
      as? [[CFString: Any]]
    let keyframe = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    let size = CMSampleBufferGetTotalSampleSize(sample)
    if keyframe {
      groups.append(Group(samples: [], start: time, bytes: 0))
    }
    guard !groups.isEmpty else { return }
    groups[groups.count - 1].samples.append(sample)
    groups[groups.count - 1].bytes += size
    bytes += size
    let sampleDuration = CMSampleBufferGetDuration(sample)
    end =
      time
      + (sampleDuration.isNumeric && sampleDuration > .zero
        ? sampleDuration : CMTime(value: 1, timescale: 30))
    let cutoff = end - CMTime(seconds: duration, preferredTimescale: 60_000)
    while groups.count > 1 && (groups[1].start <= cutoff || bytes > byteLimit) {
      bytes -= groups.removeFirst().bytes
    }
    if bytes > byteLimit {
      groups.removeAll()
      bytes = 0
    }
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    groups.removeAll()
    bytes = 0
    end = .zero
  }

  public var statistics: BufferStatistics {
    lock.lock()
    defer { lock.unlock() }
    return BufferStatistics(
      duration: min(duration, groups.first.map { CMTimeGetSeconds(end - $0.start) } ?? 0),
      bytes: bytes)
  }

  public func snapshot() throws -> ReplaySnapshot {
    lock.lock()
    defer { lock.unlock() }
    guard let first = groups.first else { throw ReplayError.empty }
    let start = max(first.start, end - CMTime(seconds: duration, preferredTimescale: 60_000))
    return ReplaySnapshot(samples: groups.flatMap(\.samples), start: start, end: end)
  }
}
