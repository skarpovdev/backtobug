import AppKit
import Carbon

enum CaptureQuality: String, Codable, CaseIterable, Identifiable {
  case efficient, balanced, sharp
  var id: String { rawValue }
  var title: String {
    switch self {
    case .efficient: return "Efficient"
    case .balanced: return "Balanced"
    case .sharp: return "Extra sharp"
    }
  }
  var maximumDimension: Int {
    switch self {
    case .efficient: return 1920
    case .balanced: return 2560
    case .sharp: return 3840
    }
  }
  var bitrate: Int {
    switch self {
    case .efficient: return 4_000_000
    case .balanced: return 8_000_000
    case .sharp: return 16_000_000
    }
  }
}

struct AppSettings: Codable, Equatable {
  var duration = 60
  var displayID: UInt32 = 0
  var quality: CaptureQuality = .balanced
  var fps = 30
  var showsCursor = true
  var showsClicks = true
  var autoStart = true
  var shortcutKey: UInt32 = UInt32(kVK_ANSI_B)
  var shortcutModifiers: UInt32 = UInt32(cmdKey | shiftKey)
  var folderPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Back to Bug", isDirectory: true).path

  var shortcutLabel: String {
    var result = ""
    if shortcutModifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if shortcutModifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if shortcutModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if shortcutModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result + Shortcut.keyLabel(shortcutKey)
  }

  static func load() -> AppSettings {
    guard let data = UserDefaults.standard.data(forKey: "settings"),
      var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    else { return AppSettings() }
    settings.duration = min(600, max(5, settings.duration))
    if ![15, 30, 60].contains(settings.fps) { settings.fps = 30 }
    return settings
  }

  func persist() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: "settings")
    }
  }
}

final class Shortcut {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  var action: (() -> Void)?

  init() {
    var event = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let shortcut = Unmanaged<Shortcut>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { shortcut.action?() }
        return noErr
      }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  func register(key: UInt32, modifiers: UInt32) -> Bool {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    let id = EventHotKeyID(signature: 0x4254_4247, id: 1)
    return RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
  }

  static func keyLabel(_ code: UInt32) -> String {
    let labels: [UInt32: String] = [
      0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
      11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
      20: "3", 21: "4", 22: "6", 23: "5", 24: "+", 25: "9", 26: "7", 27: "−", 28: "8",
      29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
      39: "’", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
      49: "Space", 50: "`", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
      103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
    ]
    return labels[code] ?? "Key \(code)"
  }

  deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
  }
}
