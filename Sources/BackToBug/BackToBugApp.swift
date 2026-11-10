import AppKit
import Combine
import SwiftUI

@main
enum BackToBugApp {
  @MainActor static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = AppModel()
  private var item: NSStatusItem!
  private let popover = NSPopover()
  private var subscriptions = Set<AnyCancellable>()
  private var savedIndicator = false
  private var saveIndicatorReset: DispatchWorkItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 400, height: 590)
    popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
    Publishers.CombineLatest3(model.$state, model.$settings, model.$errorMessage)
      .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatus() } }
      .store(in: &subscriptions)
    model.onSave = { [weak self] in
      guard let self else { return }
      self.saveIndicatorReset?.cancel()
      self.savedIndicator = true
      self.updateStatus()
      let reset = DispatchWorkItem { [weak self] in
        self?.savedIndicator = false
        self?.model.savedMessage = nil
        self?.updateStatus()
      }
      self.saveIndicatorReset = reset
      DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: reset)
    }
    model.prepare()
    updateStatus()
    if model.state == .permission { showPopover() }
  }

  private func updateStatus() {
    let symbol =
      model.errorMessage != nil
      ? "exclamationmark.circle"
      : savedIndicator
        ? "checkmark.circle"
        : model.state == .recording
          ? "arrow.counterclockwise.circle.fill" : "arrow.counterclockwise.circle"
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Back to Bug")
    image?.isTemplate = true
    item.button?.image = image
    item.button?.toolTip =
      model.errorMessage.map { "Back to Bug — \($0)" }
      ?? (savedIndicator
        ? "Back to Bug — Replay saved"
        : "Back to Bug — \(model.state == .recording ? "Recording" : "Paused") — \(model.settings.shortcutLabel) to save")
    item.button?.setAccessibilityLabel(
      "Back to Bug, \(model.state == .recording ? "recording" : "paused")")
  }

  @objc private func togglePopover() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      let save = menu.addItem(
        withTitle: "Save replay", action: #selector(saveReplay), keyEquivalent: "")
      save.target = self
      save.isEnabled = model.canSave
      menu.addItem(.separator())
      let open = menu.addItem(
        withTitle: "Open Back to Bug", action: #selector(showPopover), keyEquivalent: "")
      open.target = self
      let quit = menu.addItem(
        withTitle: "Quit Back to Bug", action: #selector(quit), keyEquivalent: "q")
      quit.target = self
      item.menu = menu
      item.button?.performClick(nil)
      item.menu = nil
    } else if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover()
    }
  }

  @objc private func showPopover() {
    guard let button = item.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  @objc private func saveReplay() { model.saveReplay() }
  @objc private func quit() { NSApp.terminate(nil) }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showPopover()
    return false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if model.isSaving {
      let alert = NSAlert()
      alert.messageText = "A replay is still being saved."
      alert.informativeText = "Wait for the save to finish before quitting."
      alert.addButton(withTitle: "Keep saving")
      alert.runModal()
      return .terminateCancel
    }
    Task {
      await model.shutdown()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
