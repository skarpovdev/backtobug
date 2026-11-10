import Carbon
import SwiftUI

private enum Theme {
  static let accent = Color(red: 0.19, green: 0.34, blue: 0.94)
  static let link = Color(nsColor: .linkColor)
  static let success = Color(nsColor: .systemGreen)
  static let card = Color(nsColor: .controlBackgroundColor)
  static let border = Color.primary.opacity(0.08)
}

struct PanelView: View {
  @ObservedObject var model: AppModel
  @State private var showsSettings = false

  var body: some View {
    VStack(spacing: 0) {
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
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 10) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Back to Bug").font(.system(size: 17, weight: .semibold))
          Text("A replay for every repro.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        HStack(spacing: 5) {
          Circle().fill(model.state == .recording ? Theme.success : Color.secondary).frame(
            width: 6, height: 6)
          Text(stateLabel).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: Capsule())
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if model.state == .permission { permissionCard } else { bufferCard }

          if let message = model.errorMessage {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
              Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              Button {
                model.errorMessage = nil
              } label: {
                Image(systemName: "xmark")
              }
              .buttonStyle(.plain).accessibilityLabel("Dismiss error")
            }
            .padding(10).background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
          }

          VStack(spacing: 0) {
            HStack(spacing: 10) {
              Image(systemName: "display").foregroundStyle(.secondary).frame(width: 20)
              VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(
                  "\(model.settings.quality.maximumDimension) px max · \(model.settings.fps) fps · No audio"
                )
                .font(.system(size: 10)).foregroundStyle(.secondary)
              }
              Spacer()
            }.padding(13)
            Divider().padding(.horizontal, 13)
            Button(action: model.toggleRecording) {
              HStack(spacing: 10) {
                Image(systemName: model.state == .recording ? "pause.circle" : "play.circle").frame(
                  width: 20)
                Text(model.state == .recording ? "Pause recording" : "Resume recording")
                Spacer()
                if model.isBusy {
                  ProgressView().controlSize(.small)
                } else {
                  Text(
                    model.state == .recording ? "Buffer clears on pause" : "Start a fresh buffer"
                  ).font(.system(size: 10)).foregroundStyle(.secondary)
                }
              }
              .font(.system(size: 12)).contentShape(Rectangle()).padding(13)
            }.buttonStyle(.plain).disabled(model.isBusy || model.state == .permission)
          }.card()

          HStack {
            sectionLabel("RECENT REPLAYS")
            Spacer()
            Button("Open folder", action: model.openFolder).font(.system(size: 11)).buttonStyle(
              .plain
            ).foregroundStyle(Theme.link)
          }
          VStack(spacing: 2) {
            if model.clips.isEmpty {
              VStack(spacing: 7) {
                Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 24))
                  .foregroundStyle(.tertiary)
                Text("Your next bug has a backstory.").font(.system(size: 12, weight: .medium))
                Text("Saved replays will appear here.").font(.system(size: 11)).foregroundStyle(
                  .secondary)
              }
              .frame(maxWidth: .infinity, minHeight: 88)
            } else {
              ForEach(model.clips) { clip in
                HStack(spacing: 10) {
                  Button {
                    NSWorkspace.shared.open(clip.url)
                  } label: {
                    HStack(spacing: 10) {
                      Image(systemName: "play.rectangle.fill").font(.system(size: 22))
                        .foregroundStyle(Theme.link)
                        .frame(width: 38, height: 34).background(
                          Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                      VStack(alignment: .leading, spacing: 3) {
                        Text(
                          clip.date,
                          format: .dateTime.month(.abbreviated).day().hour().minute().second()
                        ).font(.system(size: 12, weight: .medium))
                        Text(
                          "MP4 · \(ByteCountFormatter.string(fromByteCount: Int64(clip.bytes), countStyle: .file))"
                        ).font(.system(size: 10)).foregroundStyle(.secondary)
                      }
                      Spacer()
                    }.contentShape(Rectangle())
                  }.buttonStyle(.plain).help("Play replay")
                  Button {
                    NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                  } label: {
                    Image(systemName: "folder").foregroundStyle(.secondary).padding(6)
                  }.buttonStyle(.plain).accessibilityLabel("Show replay in Finder")
                }.padding(.vertical, 4)
              }
            }
          }
        }.padding(1)
      }.scrollIndicators(.hidden)
      Divider()
      HStack {
        Button {
          showsSettings = true
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .disabled(model.isBusy)
        Spacer()
        Text(
          "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")"
        )
        .font(.system(size: 10)).foregroundStyle(.secondary)
        Spacer()
        Button {
          NSApp.terminate(nil)
        } label: {
          Label("Quit", systemImage: "power")
        }
      }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.secondary)
    }
    .padding(22)
  }

  private var bufferCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        sectionLabel("REPLAY BUFFER")
        Spacer()
        Text(
          model.state == .recording
            ? (model.bufferedSeconds >= Double(model.settings.duration) - 0.1
              ? "Ready when you are" : "Filling up…") : "Recording paused"
        )
        .font(.system(size: 10)).foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(clock(model.bufferedSeconds)).font(
          .system(size: 43, weight: .medium, design: .rounded)
        ).monospacedDigit()
        Text("/ \(clock(Double(model.settings.duration)))").font(
          .system(size: 17, weight: .medium, design: .rounded)
        ).foregroundStyle(.secondary)
        Spacer()
        Image(systemName: "arrow.counterclockwise").font(.system(size: 30, weight: .light))
          .foregroundStyle(Theme.link)
          .accessibilityHidden(true)
      }
      HStack(spacing: 3) {
        ForEach(0..<40) { index in
          Capsule().fill(
            Double(index) / 40 < model.bufferedSeconds / Double(model.settings.duration)
              ? Theme.accent : Color.primary.opacity(0.07)
          )
          .frame(height: 17)
        }
      }.accessibilityLabel(
        "\(Int(model.bufferedSeconds)) of \(model.settings.duration) seconds buffered")
      Button(action: model.saveReplay) {
        HStack(spacing: 8) {
          if model.isSaving {
            ProgressView().controlSize(.small).tint(.white)
          } else {
            Image(systemName: model.savedMessage == nil ? "square.and.arrow.down" : "checkmark")
          }
          Text(model.isSaving ? "Saving replay…" : model.savedMessage ?? "Save replay").fontWeight(
            .semibold)
          Spacer()
          Text(model.settings.shortcutLabel).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 4).background(
              .white.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
        }.font(.system(size: 13)).padding(.horizontal, 14).frame(height: 43).contentShape(
          Rectangle())
      }
      .buttonStyle(.plain).foregroundStyle(.white)
      .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 10))
      .opacity(model.canSave || model.isSaving ? 1 : 0.45).disabled(!model.canSave)
      .keyboardShortcut("s", modifiers: .command)
      if !model.shortcutAvailable {
        Text("Shortcut unavailable. Choose another in Settings.").font(.system(size: 10))
          .foregroundStyle(.orange)
      }
    }.padding(16).card()
  }

  private var permissionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "display.badge.checkmark").font(.system(size: 27)).foregroundStyle(
        Theme.link)
      Text("Be ready for the next bug.").font(.system(size: 19, weight: .semibold))
      Text(
        "Allow screen recording to keep a rolling replay. Video stays on this Mac and is saved only when you choose."
      )
      .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
      Button {
        Task { await model.start() }
      } label: {
        Text("Enable screen recording").frame(maxWidth: .infinity).frame(height: 30)
      }.buttonStyle(.borderedProminent).controlSize(.large)
      Button("Open System Settings", action: model.openPermissions).font(.system(size: 11))
        .buttonStyle(.plain).foregroundStyle(Theme.link)
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
  Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
}

extension View {
  fileprivate func card() -> some View {
    background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
  }
}

struct SettingsView: View {
  @ObservedObject var model: AppModel
  let close: () -> Void
  @State private var draft: AppSettings
  @State private var recordingShortcut = false
  @State private var shortcutMonitor: Any?
  @State private var applying = false

  init(model: AppModel, close: @escaping () -> Void) {
    self.model = model
    self.close = close
    _draft = State(initialValue: model.settings)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Button(action: close) {
          Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(
            width: 26, height: 30)
        }
        .buttonStyle(.plain).accessibilityLabel("Back to replay").disabled(applying)
        Text("Settings").font(.system(size: 19, weight: .semibold))
        Spacer()
        Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 12) {
            sectionLabel("CAPTURE")
            HStack {
              Text("Replay length")
              Spacer()
              TextField("Seconds", value: $draft.duration, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing).frame(width: 60).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Replay length in seconds")
              Text("sec").foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
              ForEach([15, 30, 60, 120, 300], id: \.self) { duration in
                Button(duration < 60 ? "\(duration)s" : "\(duration / 60)m") {
                  draft.duration = duration
                }
                .buttonStyle(.bordered).tint(draft.duration == duration ? Theme.accent : .secondary)
                .frame(maxWidth: .infinity)
              }
            }
            Picker("Display", selection: $draft.displayID) {
              Text("Main display").tag(UInt32(0))
              ForEach(model.displays) { Text($0.name).tag($0.id) }
            }
            Picker("Quality", selection: $draft.quality) {
              ForEach(CaptureQuality.allCases) {
                Text("\($0.title) · \($0.maximumDimension) px").tag($0)
              }
            }
            Picker("Frame rate", selection: $draft.fps) {
              ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
            }
            Toggle("Include cursor", isOn: $draft.showsCursor)
            if #available(macOS 15, *) {
              Toggle("Highlight mouse clicks", isOn: $draft.showsClicks)
            }
            Text(
              "5–600 seconds. The buffer uses up to 512 MB; high quality may hold a shorter replay."
            )
            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(
              horizontal: false, vertical: true)
          }.padding(14).card()

          VStack(alignment: .leading, spacing: 12) {
            sectionLabel("SAVE REPLAYS")
            HStack {
              Text("Global shortcut")
              Spacer()
              Button(recordingShortcut ? "Press shortcut…" : draft.shortcutLabel) {
                beginShortcutRecording()
              }
              .buttonStyle(.bordered).help("Use Command or Control with a key. Escape cancels.")
            }
            Text("Use ⌘ or ⌃ with a key. Esc cancels.").font(.system(size: 10)).foregroundStyle(
              .secondary)
            Divider()
            HStack {
              Image(systemName: "folder").foregroundStyle(Theme.link)
              Text(URL(fileURLWithPath: draft.folderPath).lastPathComponent).lineLimit(1)
                .truncationMode(.middle)
              Spacer()
              Button("Choose…", action: chooseFolder).buttonStyle(.bordered)
            }
            Text(draft.folderPath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
              .truncationMode(.middle)
          }.padding(14).card()

          VStack(alignment: .leading, spacing: 12) {
            sectionLabel("GENERAL")
            Toggle("Start recording when app opens", isOn: $draft.autoStart)
            Toggle(
              "Launch at login",
              isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
          }.padding(14).card()
          Text("Screen video only. Changing capture settings starts a fresh buffer.")
            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(
              horizontal: false, vertical: true)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
      }.scrollIndicators(.hidden)
      Button {
        stopShortcutRecording()
        applying = true
        Task {
          await model.apply(draft)
          close()
        }
      } label: {
        HStack {
          if applying { ProgressView().controlSize(.small) }
          Text(applying ? "Applying…" : "Done").fontWeight(.semibold)
        }.frame(maxWidth: .infinity).frame(height: 32)
      }.buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(applying || !(5...600).contains(draft.duration))
    }
    .padding(22)
    .onDisappear { stopShortcutRecording() }
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
