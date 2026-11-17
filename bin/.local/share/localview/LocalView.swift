// LocalView: a borderless pane showing one local web page (tinymist's Typst preview)
// beside Zed, and nothing else: no title bar, tabs, address bar, Dock icon, menus or
// app-switcher entry. `typview` builds and opens it.
//
//   LocalView URL
//
// It belongs to Zed: it floats beside Zed's window only while Zed is the active app with
// a .typ file in front, and hides otherwise. Clicking it doesn't take focus from Zed, so
// click-to-jump lands you back in the editor. It quits after a minute of Zed showing
// other files (you closed the Typst file), when Zed quits, or when the preview server is
// gone for 10 seconds.
//
// On launch (and each `typview`) it splits Zed's front window: Zed keeps the left half,
// the pane takes the right. If Zed's window is already narrow, the pane fills the space
// beside it instead. Needs LocalView in System Settings > Privacy > Accessibility (asked
// once) to see and resize Zed's window.
//
// Keys (after clicking the pane): Cmd-R reload, Cmd-+ / Cmd-- / Cmd-0 zoom, Cmd-W close.
import AppKit
import WebKit

let target = URL(string: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "http://127.0.0.1:23635")!
let zedID = "dev.zed.Zed"
let quitAfterOtherFiles = 60.0  // seconds of Zed showing non-Typst files
let quitAfterOffline = 10  // failed server checks in a row

// A pane that can take keys (for Cmd-R etc.) without activating the app
final class Pane: NSPanel {
  override var canBecomeKey: Bool { true }
}

// ── Zed's front window, through the Accessibility API (top-left screen coordinates) ──
func zedApp() -> NSRunningApplication? {
  NSRunningApplication.runningApplications(withBundleIdentifier: zedID).first
}

func zedWindow() -> AXUIElement? {
  guard AXIsProcessTrusted(), let zed = zedApp() else { return nil }
  var win: CFTypeRef?
  let app = AXUIElementCreateApplication(zed.processIdentifier)
  guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success
  else { return nil }
  return (win as! AXUIElement)
}

func axFrame(_ win: AXUIElement) -> CGRect? {
  var pos: CFTypeRef?
  var size: CFTypeRef?
  var p = CGPoint.zero
  var s = CGSize.zero
  guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &pos) == .success,
    AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &size) == .success,
    AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s)
  else { return nil }
  return CGRect(origin: p, size: s)
}

func axSetWidth(_ win: AXUIElement, _ frame: CGRect, _ width: CGFloat) {
  var s = CGSize(width: width, height: frame.height)
  if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
}

func axTitle(_ win: AXUIElement) -> String? {
  var t: CFTypeRef?
  AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &t)
  return t as? String
}

final class Delegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  var pane: Pane!
  var web: WKWebView!
  var otherFilesSince: Date?
  var offline = 0
  var placedBesideZed = false

  func applicationDidFinishLaunching(_ note: Notification) {
    _ = AXIsProcessTrustedWithOptions(
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)

    pane = Pane(
      contentRect: NSRect(x: 200, y: 200, width: 900, height: 1100),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    pane.hasShadow = false
    pane.hidesOnDeactivate = false
    pane.isReleasedWhenClosed = false
    pane.becomesKeyOnlyIfNeeded = true
    pane.level = .floating
    // not in Cmd-` cycling, Mission Control or window switchers
    pane.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    pane.backgroundColor = .windowBackgroundColor

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()  // nothing written to disk
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.allowsMagnification = true
    pane.contentView = web
    web.load(URLRequest(url: target))

    layout()
    update()

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] e in self.handleKey(e) ? nil : e }
    let ws = NSWorkspace.shared.notificationCenter
    ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
      [unowned self] _ in self.update()
    }
    ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      if app?.bundleIdentifier == zedID { NSApp.terminate(nil) }
    }
    // Zed's tab changes have no notification: a cheap title check twice a second
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [unowned self] _ in self.update() }
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in self.checkServer() }
  }

  // `typview` again (open -a on the running app): place the pane beside Zed once more
  func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
    layout()
    update()
    return false
  }

  // Zed keeps the left part of its screen, the pane gets the rest
  func layout() {
    guard let primary = NSScreen.screens.first else { return }
    guard let win = zedWindow(), let z = axFrame(win) else {
      // can't see Zed yet (no Accessibility): right half of the screen, never over the editor
      let area = (NSScreen.main ?? primary).visibleFrame
      pane.setFrame(NSRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height), display: true)
      return
    }
    placedBesideZed = true
    // AX counts y down from the top of the primary screen, AppKit up from its bottom
    let zed = NSRect(x: z.minX, y: primary.frame.height - z.maxY, width: z.width, height: z.height)
    let screen = NSScreen.screens.first { $0.frame.intersects(zed) } ?? primary
    let area = screen.visibleFrame
    var left = zed.maxX
    if zed.maxX > area.maxX - 300 {  // Zed fills the screen: split it
      let half = (zed.width / 2).rounded()
      axSetWidth(win, z, half)
      left = zed.minX + half
    }
    pane.setFrame(NSRect(x: left, y: zed.minY, width: area.maxX - left, height: zed.height), display: true)
  }

  func update() {
    // Accessibility granted while running: move beside Zed now
    if !placedBesideZed && AXIsProcessTrusted() { layout() }
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    let zedActive = front == zedID || front == Bundle.main.bundleIdentifier
    // without Accessibility we can't see the file: assume Typst
    let typst = zedWindow().flatMap(axTitle).map { $0.hasSuffix(".typ") } ?? true

    if zedActive && typst {
      if !pane.isVisible { pane.orderFrontRegardless() }
    } else if pane.isVisible {
      pane.orderOut(nil)
    }

    if zedActive && !typst {
      if otherFilesSince == nil { otherFilesSince = Date() }
      if Date().timeIntervalSince(otherFilesSince!) > quitAfterOtherFiles { NSApp.terminate(nil) }
    } else {
      otherFilesSince = nil
    }
  }

  func handleKey(_ e: NSEvent) -> Bool {
    guard e.modifierFlags.contains(.command) else { return false }
    switch e.charactersIgnoringModifiers {
    case "r": web.reload()
    case "=", "+": web.pageZoom = min(web.pageZoom * 1.1, 4)
    case "-": web.pageZoom = max(web.pageZoom / 1.1, 0.25)
    case "0": web.pageZoom = 1
    case "w", "q": NSApp.terminate(nil)
    default: return false
    }
    return true
  }

  func checkServer() {
    var req = URLRequest(url: target)
    req.httpMethod = "HEAD"
    req.timeoutInterval = 1
    URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        self.offline = response == nil ? self.offline + 1 : 0
        if self.offline >= quitAfterOffline { NSApp.terminate(nil) }
      }
    }.resume()
  }

  // Clicked links that leave localhost go to the real browser
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if action.navigationType == .linkActivated, let url = action.request.url,
      let host = url.host, !["127.0.0.1", "localhost", "::1"].contains(host)
    {
      NSWorkspace.shared.open(url)
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  // Server not up yet, or restarted: try again shortly
  func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { webView.load(URLRequest(url: target)) }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon, menu bar or Cmd-Tab entry
app.run()
