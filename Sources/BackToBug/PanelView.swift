import Carbon
import SwiftUI

private enum Theme {
  static let accent = Color(nsColor: .systemBlue)
  static let link = Color(nsColor: .linkColor)
  static let success = Color(nsColor: .systemGreen)
  static let card = Color(nsColor: .controlBackgroundColor)
  static let border = Color.primary.opacity(0.08)
}

struct PanelView: View {
  @ObservedObject var model: AppModel
  @State private var showsSettings = false

  var body: some View {
    Group {
      if showsSettings {
        SettingsView(model: model) { showsSettings = false }
      } else {
        dashboard
      }
    }
    .frame(width: 400, height: 590)
    .background(.regularMaterial)
    .tint(Theme.accent)
    .onAppear { Task { await model.refreshClips() } }
  }

  private var dashboard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 9))
          .accessibilityHidden(true)
        Text("Back to Bug").font(.system(size: 16, weight: .semibold))
        Spacer()
        HStack(spacing: 5) {
          Circle().fill(model.state == .recording ? Theme.success : Color.secondary)
            .frame(width: 6, height: 6)
          Text(stateLabel).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: Capsule())
      }

      if model.state == .permission { permissionCard } else { bufferCard }

      if let message = model.errorMessage {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            .accessibilityHidden(true)
          ScrollView {
            Text(message).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
          }.frame(maxHeight: 50)
          Button {
            model.errorMessage = nil
          } label: {
            Image(systemName: "xmark").frame(width: 20, height: 20)
          }
          .buttonStyle(.borderless).accessibilityLabel("Dismiss error")
        }
        .padding(10).background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
      }

      HStack(spacing: 10) {
        Image(systemName: "display").font(.system(size: 19)).foregroundStyle(.secondary)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(model.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
            .truncationMode(.middle).help(model.displayName)
          Text(
            "\(model.settings.quality.maximumDimension) px · \(model.settings.fps) fps · No audio"
          )
          .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer(minLength: 4)
        Button(action: model.toggleRecording) {
          if model.isBusy {
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
          } else {
            Image(systemName: model.state == .recording ? "pause.fill" : "play.fill")
              .frame(width: 16, height: 16)
          }
        }
        .buttonStyle(.bordered).controlSize(.regular)
        .disabled(model.isBusy || model.state == .permission)
        .accessibilityLabel(model.state == .recording ? "Pause recording" : "Resume recording")
        .help(
          model.state == .recording
            ? "Pause recording and clear the buffer" : "Resume recording with a fresh buffer")
      }.padding(12).card()

      VStack(alignment: .leading, spacing: 10) {
        HStack {
          sectionLabel("RECENT REPLAYS")
          Spacer()
          Button("Open folder", action: model.openFolder)
            .font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(Theme.link)
        }
        if model.clips.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 24))
              .foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No saved replays yet").font(.system(size: 12, weight: .medium))
            Text("Save a replay when you find a bug.").font(.system(size: 11))
              .foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            VStack(spacing: 0) {
              ForEach(model.clips) { clip in
                HStack(spacing: 8) {
                  Button {
                    NSWorkspace.shared.open(clip.url)
                  } label: {
                    HStack(spacing: 10) {
                      Image(systemName: "play.fill").font(.system(size: 13))
                        .foregroundStyle(Theme.link)
                        .frame(width: 36, height: 36)
                        .background(
                          Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)
                        )
                        .accessibilityHidden(true)
                      VStack(alignment: .leading, spacing: 4) {
                        Text(
                          clip.date,
                          format: .dateTime.month(.abbreviated).day().hour().minute().second()
                        )
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(
                          "MP4 · \(ByteCountFormatter.string(fromByteCount: Int64(clip.bytes), countStyle: .file))"
                        )
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                      }
                      Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                  }.buttonStyle(.plain).help("Play replay")
                  Button {
                    NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                  } label: {
                    Image(systemName: "folder").frame(width: 28, height: 30)
                  }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel("Show replay in Finder")
                }.padding(.vertical, 6)
              }
            }
          }.scrollIndicators(.automatic)
        }
      }.frame(maxHeight: .infinity)

      Divider()
      HStack(spacing: 12) {
        Button {
          showsSettings = true
        } label: {
          Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity)
        }.disabled(model.isBusy)
        Text(
          "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1")"
        )
        .font(.system(size: 10)).foregroundStyle(.secondary)
        Button {
          NSApp.terminate(nil)
        } label: {
          Label("Quit", systemImage: "power").frame(maxWidth: .infinity)
        }
      }.font(.system(size: 12)).buttonStyle(.bordered).controlSize(.regular)
    }.padding(20)
  }

  private var bufferCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        sectionLabel("REPLAY BUFFER")
        Spacer()
        Text(
          model.state == .recording
            ? (model.bufferedSeconds >= Double(model.settings.duration) - 0.1
              ? "Ready" : "Filling…")
            : model.state == .starting ? "Starting…" : "Paused"
        )
        .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(clock(model.bufferedSeconds))
          .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
        Text("/ \(clock(Double(model.settings.duration)))")
          .font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        Spacer()
      }
      ProgressView(
        value: min(model.bufferedSeconds, Double(model.settings.duration)),
        total: Double(model.settings.duration)
      )
      .progressViewStyle(.linear)
      .accessibilityLabel("Replay buffer")
      .accessibilityValue("\(Int(model.bufferedSeconds)) of \(model.settings.duration) seconds")
      Button(action: model.saveReplay) {
        HStack(spacing: 8) {
          if model.isSaving {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: model.savedMessage == nil ? "square.and.arrow.down" : "checkmark")
          }
          Text(model.isSaving ? "Saving replay…" : model.savedMessage ?? "Save replay")
            .fontWeight(.semibold)
          Spacer()
          Text(model.settings.shortcutLabel).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
        }.font(.system(size: 13)).frame(maxWidth: .infinity, minHeight: 26)
      }
      .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canSave)
      .keyboardShortcut("s", modifiers: .command)
      if !model.shortcutAvailable {
        Text("Shortcut unavailable. Choose another in Settings.")
          .font(.system(size: 11)).foregroundStyle(.orange)
      }
    }.padding(16).card()
  }

  private var permissionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Enable screen recording", systemImage: "display.badge.checkmark")
        .font(.system(size: 17, weight: .semibold))
      Text(
        "Allow screen access to keep a rolling replay. The replay stays in memory until you save it."
      )
      .font(.system(size: 12)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        Task { await model.start() }
      } label: {
        Text("Enable screen recording").frame(maxWidth: .infinity, minHeight: 24)
      }.buttonStyle(.borderedProminent).controlSize(.large)
      Button("Open System Settings", action: model.openPermissions)
        .font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(Theme.link)
    }.padding(16).card()
  }

  private var stateLabel: String {
    switch model.state {
    case .permission: return "Set up"
    case .paused: return "Paused"
    case .starting: return "Starting"
    case .recording: return "Recording"
    }
  }

  private func clock(_ value: Double) -> String {
    let seconds = max(0, Int(value))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

private func sectionLabel(_ text: String) -> some View {
  Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
}

extension View {
  fileprivate func card() -> some View {
    background(Theme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
  }
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  let close: () -> Void
  @State private var draft: AppSettings
  @State private var draftLoginEnabled: Bool
  @State private var recordingShortcut = false
  @State private var shortcutMonitor: Any?
  @State private var applying = false

  init(model: AppModel, close: @escaping () -> Void) {
    self.model = model
    self.close = close
    _draft = State(initialValue: model.settings)
    _draftLoginEnabled = State(initialValue: model.loginEnabled)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Settings").font(.system(size: 18, weight: .semibold))
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 14) {
            sectionLabel("CAPTURE")
            settingsRow("Replay length") {
              TextField("Seconds", value: $draft.duration, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing).frame(width: 64).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Replay length in seconds")
              Text("sec").foregroundStyle(.secondary)
            }
            Picker("Replay length presets", selection: $draft.duration) {
              ForEach([15, 30, 60, 120, 300], id: \.self) { duration in
                Text(duration < 60 ? "\(duration)s" : "\(duration / 60)m").tag(duration)
              }
              if ![15, 30, 60, 120, 300].contains(draft.duration) {
                Text("Custom").tag(draft.duration)
              }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
              .accessibilityLabel("Replay length presets")
            if !(5...600).contains(draft.duration) {
              Text("Enter a length from 5 to 600 seconds.")
                .font(.system(size: 11)).foregroundStyle(.red)
            }
            Divider()
            settingsRow("Display") {
              Picker("Display", selection: $draft.displayID) {
                Text("Main display").tag(UInt32(0))
                ForEach(model.displays) { Text($0.name).tag($0.id) }
              }.labelsHidden().frame(width: 190, alignment: .trailing)
            }
            settingsRow("Quality") {
              Picker("Quality", selection: $draft.quality) {
                ForEach(CaptureQuality.allCases) {
                  Text("\($0.title) · \($0.maximumDimension) px").tag($0)
                }
              }.labelsHidden().frame(width: 190, alignment: .trailing)
            }
            settingsRow("Frame rate") {
              Picker("Frame rate", selection: $draft.fps) {
                ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
              }.labelsHidden().frame(width: 190, alignment: .trailing)
            }
            Divider()
            settingsRow("Include cursor") {
              Toggle("Include cursor", isOn: $draft.showsCursor).labelsHidden()
            }
            if #available(macOS 15, *) {
              settingsRow("Highlight mouse clicks") {
                Toggle("Highlight mouse clicks", isOn: $draft.showsClicks).labelsHidden()
              }
            }
            Text("The buffer uses up to 512 MB. High quality may hold a shorter replay.")
              .font(.system(size: 11)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }.padding(14).card()

          VStack(alignment: .leading, spacing: 12) {
            sectionLabel("SAVE REPLAYS")
            settingsRow("Global shortcut") {
              Button(recordingShortcut ? "Press shortcut…" : draft.shortcutLabel) {
                beginShortcutRecording()
              }.buttonStyle(.bordered)
                .accessibilityLabel(
                  "Global shortcut, \(recordingShortcut ? "press a shortcut" : draft.shortcutLabel)"
                )
                .help("Use Command or Control with a key. Escape cancels.")
            }
            Text("Use ⌘ or ⌃ with a key. Esc cancels.")
              .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            settingsRow("Save location") {
              Button("Choose…", action: chooseFolder).buttonStyle(.bordered)
            }
            Label(URL(fileURLWithPath: draft.folderPath).lastPathComponent, systemImage: "folder")
              .lineLimit(1).truncationMode(.middle)
            Text(draft.folderPath).font(.system(size: 11)).foregroundStyle(.secondary)
              .lineLimit(2).truncationMode(.middle).help(draft.folderPath)
          }.padding(14).card()

          VStack(alignment: .leading, spacing: 14) {
            sectionLabel("GENERAL")
            settingsRow("Start recording when app opens") {
              Toggle("Start recording when app opens", isOn: $draft.autoStart).labelsHidden()
            }
            settingsRow("Launch at login") {
              Toggle("Launch at login", isOn: $draftLoginEnabled).labelsHidden()
            }
          }.padding(14).card()
          Text("Screen video only. Changing capture settings starts a fresh buffer.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
          .padding(1).disabled(applying)
      }.scrollIndicators(.automatic)
      Divider()
      HStack {
        Button("Cancel", action: close).buttonStyle(.bordered).disabled(applying)
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button {
          stopShortcutRecording()
          applying = true
          Task {
            await model.apply(draft)
            if draftLoginEnabled != model.loginEnabled {
              model.setLoginEnabled(draftLoginEnabled)
            }
            close()
          }
        } label: {
          HStack(spacing: 6) {
            if applying { ProgressView().controlSize(.small) }
            Text(applying ? "Applying…" : "Save changes").fontWeight(.semibold)
          }
        }.buttonStyle(.borderedProminent)
          .disabled(applying || recordingShortcut || !(5...600).contains(draft.duration))
          .keyboardShortcut(.defaultAction)
      }.controlSize(.large)
    }
    .padding(20)
    .onDisappear { stopShortcutRecording() }
  }

  private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    HStack(spacing: 8) {
      Text(title)
      Spacer(minLength: 8)
      content()
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose where Back to Bug saves your replays."
    panel.directoryURL = URL(fileURLWithPath: draft.folderPath)
    panel.begin { response in
      if response == .OK, let url = panel.url { draft.folderPath = url.path }
    }
  }

  private func beginShortcutRecording() {
    guard !recordingShortcut else { return }
    recordingShortcut = true
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        stopShortcutRecording()
        return nil
      }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard flags.contains(.command) || flags.contains(.control) else {
        NSSound.beep()
        return nil
      }
      var modifiers: UInt32 = 0
      if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
      if flags.contains(.control) { modifiers |= UInt32(controlKey) }
      if flags.contains(.option) { modifiers |= UInt32(optionKey) }
      if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
      draft.shortcutKey = UInt32(event.keyCode)
      draft.shortcutModifiers = modifiers
      stopShortcutRecording()
      return nil
    }
  }

  private func stopShortcutRecording() {
    if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
    shortcutMonitor = nil
    recordingShortcut = false
  }
}
