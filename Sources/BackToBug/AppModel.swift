import AppKit
import Combine
import ReplayCore
import ScreenCaptureKit
import ServiceManagement

enum RecorderState {
  case permission, paused, starting, recording
}

struct DisplayChoice: Identifiable {
  let id: UInt32
  let name: String
}

struct SavedClip: Identifiable {
  let url: URL
  let date: Date
  let bytes: Int
  var id: URL { url }
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var settings = AppSettings.load()
  @Published private(set) var state: RecorderState = .paused
  @Published private(set) var bufferedSeconds = 0.0
  @Published private(set) var displays: [DisplayChoice] = []
  @Published private(set) var clips: [SavedClip] = []
  @Published private(set) var isSaving = false
  @Published var errorMessage: String?
  @Published var savedMessage: String?
  @Published var shortcutAvailable = true
  @Published var loginEnabled = SMAppService.mainApp.status == .enabled
  let shortcut = Shortcut()
  var onSave: (() -> Void)?
  private var engine: CaptureEngine?
  private var generation = UUID()
  private var clipsOperation = UUID()
  private var timer: Timer?
  private var resumeAfterSleep = false
  private var observers: [NSObjectProtocol] = []

  var isBusy: Bool { state == .starting }
  var canSave: Bool { state == .recording && bufferedSeconds > 0 && !isSaving }
  var displayName: String {
    displays.first(where: {
      $0.id == (settings.displayID == 0 ? CGMainDisplayID() : settings.displayID)
    })?.name ?? displays.first?.name ?? "Main display"
  }

  func prepare() {
    shortcut.action = { [weak self] in self?.saveReplay() }
    registerShortcut()
    state = CGPreflightScreenCaptureAccess() ? .paused : .permission
    timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let engine = self.engine else { return }
        let statistics = engine.buffer.statistics
        self.bufferedSeconds = statistics.duration
      }
    }
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
      NSWorkspace.screensDidSleepNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in
            guard let self else { return }
            if self.state == .recording || self.state == .starting {
              self.resumeAfterSleep = true
              await self.stop()
            }
          }
        })
    }
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
      NSWorkspace.screensDidWakeNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in
            guard let self, self.resumeAfterSleep else { return }
            self.resumeAfterSleep = false
            await self.start()
          }
        })
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.state == .recording else { return }
          await self.stop()
          await self.start()
        }
      })
    Task {
      await refreshClips()
      if state != .permission && settings.autoStart { await start() }
    }
  }

  func start() async {
    guard state != .starting && state != .recording else { return }
    state = .starting
    errorMessage = nil
    let operation = UUID()
    generation = operation
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        true, onScreenWindowsOnly: true)
      guard generation == operation else { return }
      displays = content.displays.map { display in
        let screen = NSScreen.screens.first {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            == display.displayID
        }
        return DisplayChoice(
          id: display.displayID, name: screen?.localizedName ?? "Display \(display.displayID)")
      }
      let wantedID = settings.displayID == 0 ? CGMainDisplayID() : settings.displayID
      guard
        let display = content.displays.first(where: { $0.displayID == wantedID })
          ?? content.displays.first
      else {
        throw ReplayError.export("No display is available. Connect a display and resume recording.")
      }
      let capture = CaptureEngine(duration: settings.duration) { [weak self] error in
        Task { @MainActor in
          guard let self, self.generation == operation else { return }
          self.errorMessage = error.localizedDescription
          await self.stop()
        }
      }
      engine = capture
      let excluded = content.applications.filter {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier
      }
      try await capture.start(display: display, applications: excluded, settings: settings)
      guard generation == operation else {
        await capture.stop()
        return
      }
      state = .recording
    } catch {
      guard generation == operation else { return }
      await stop()
      if !CGPreflightScreenCaptureAccess() {
        state = .permission
        errorMessage =
          "Allow Back to Bug in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
      } else {
        errorMessage = error.localizedDescription
      }
    }
  }

  func stop() async {
    generation = UUID()
    let capture = engine
    engine = nil
    state = .paused
    bufferedSeconds = 0
    await capture?.stop()
  }

  func toggleRecording() {
    resumeAfterSleep = false
    Task {
      if state == .recording { await stop() } else { await start() }
    }
  }

  func saveReplay() {
    guard canSave, let capture = engine else { return }
    isSaving = true
    errorMessage = nil
    savedMessage = nil
    let folder = URL(fileURLWithPath: settings.folderPath, isDirectory: true)
    Task {
      defer { isSaving = false }
      do {
        let snapshot = try await capture.snapshot()
        try await Task.detached(priority: .userInitiated) {
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let formatter = DateFormatter()
          formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
          let name =
            "Back to Bug \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).mp4"
          let url = folder.appendingPathComponent(name)
          try await ReplayExporter.save(snapshot, to: url)
        }.value
        savedMessage = "Saved \(Int(snapshot.duration.rounded())) seconds"
        await refreshClips()
        onSave?()
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func apply(_ value: AppSettings) async {
    let wasRecording = state == .recording
    let requiresRestart =
      settings.duration != value.duration || settings.displayID != value.displayID
      || settings.quality != value.quality || settings.fps != value.fps
      || settings.showsCursor != value.showsCursor || settings.showsClicks != value.showsClicks
    settings = value
    settings.persist()
    registerShortcut()
    if requiresRestart && wasRecording {
      await stop()
      await start()
    }
    await refreshClips()
  }

  func registerShortcut() {
    shortcutAvailable = shortcut.register(
      key: settings.shortcutKey, modifiers: settings.shortcutModifiers)
  }

  func setLoginEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginEnabled = SMAppService.mainApp.status == .enabled
      if enabled && !loginEnabled { SMAppService.openSystemSettingsLoginItems() }
    } catch { errorMessage = "Couldn’t change launch at login: \(error.localizedDescription)" }
  }

  func refreshClips() async {
    let operation = UUID()
    clipsOperation = operation
    let folder = URL(fileURLWithPath: settings.folderPath, isDirectory: true)
    let result = await Task.detached(priority: .utility) {
      let files =
        (try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
          options: .skipsHiddenFiles)) ?? []
      return files.filter {
        $0.pathExtension == "mp4" && $0.lastPathComponent.hasPrefix("Back to Bug ")
      }
      .compactMap { url -> SavedClip? in
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]) else {
          return nil
        }
        return SavedClip(
          url: url, date: values.creationDate ?? .distantPast, bytes: values.fileSize ?? 0)
      }.sorted { $0.date > $1.date }.prefix(3).map { $0 }
    }.value
    guard clipsOperation == operation && folder.path == settings.folderPath else { return }
    clips = result
  }

  func openFolder() {
    let url = URL(fileURLWithPath: settings.folderPath, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      NSWorkspace.shared.open(url)
    } catch { errorMessage = error.localizedDescription }
  }

  func openPermissions() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
  }

  func shutdown() async {
    timer?.invalidate()
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      NotificationCenter.default.removeObserver(observer)
    }
    await stop()
  }
}
