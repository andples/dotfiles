// LocalView: a borderless window showing one local web page (tinymist's Typst preview)
// and nothing else: no title bar, tabs, address bar, Dock icon or menus. `typview`
// builds and opens it.
//
//   LocalView URL [X Y W H]    X Y W H: the window frame, top-left origin (like AppleScript)
//
// Keys: Cmd-R reload, Cmd-+ / Cmd-- / Cmd-0 zoom, Cmd-W or Cmd-Q close.
// Links off localhost open in the default browser.
//
// It follows Zed (checked once a second, cheaply):
//   - hides while Zed's active file isn't a .typ file, comes back when one is
//     (needs LocalView in System Settings > Privacy > Accessibility; asked once)
//   - quits when hidden for a minute (you closed the Typst file), when Zed quits,
//     or when the preview server is gone for 10 seconds
import AppKit
import WebKit

let args = CommandLine.arguments
let target = URL(string: args.count > 1 ? args[1] : "http://127.0.0.1:23635")!
let zedBundle = "dev.zed.Zed"
let hiddenLimit = 60.0  // seconds hidden before quitting
let offlineLimit = 10  // failed server checks before quitting

var requestedFrame: NSRect?
if args.count >= 6, let x = Double(args[2]), let y = Double(args[3]),
  let w = Double(args[4]), let h = Double(args[5])
{
  // AppKit counts y from the bottom of the primary screen
  let primary = NSScreen.screens.first?.frame.height ?? 0
  requestedFrame = NSRect(x: x, y: primary - y - h, width: w, height: h)
}

// Borderless windows can't take keyboard focus unless they say so
final class PaneWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class Delegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  var window: PaneWindow!
  var web: WKWebView!
  var hiddenSince: Date?
  var offline = 0

  func applicationDidFinishLaunching(_ note: Notification) {
    let frame = requestedFrame ?? NSRect(x: 200, y: 200, width: 900, height: 1100)
    window = PaneWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    window.backgroundColor = .windowBackgroundColor
    window.setFrame(frame, display: true)

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()  // nothing written to disk
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.allowsMagnification = true
    window.contentView = web
    web.load(URLRequest(url: target))
    window.orderFront(nil)

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] event in
      self.handleKey(event) ? nil : event
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      if app?.bundleIdentifier == zedBundle { NSApp.terminate(nil) }
    }
    // ask for Accessibility once, for following Zed's active file
    _ = AXIsProcessTrustedWithOptions(
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in self.tick() }
  }

  func handleKey(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command) else { return false }
    switch event.charactersIgnoringModifiers {
    case "r": web.reload()
    case "=", "+": web.pageZoom = min(web.pageZoom * 1.1, 4)
    case "-": web.pageZoom = max(web.pageZoom / 1.1, 0.25)
    case "0": web.pageZoom = 1
    case "w", "q": NSApp.terminate(nil)
    default: return false
    }
    return true
  }

  func tick() {
    if NSRunningApplication.runningApplications(withBundleIdentifier: zedBundle).isEmpty {
      NSApp.terminate(nil)
    }
    checkServer()
    guard let typ = zedShowsTypst() else { return }  // no Accessibility: always shown
    if typ {
      hiddenSince = nil
      if !window.isVisible { window.orderFront(nil) }
    } else {
      if window.isVisible { window.orderOut(nil) }
      if hiddenSince == nil { hiddenSince = Date() }
      if Date().timeIntervalSince(hiddenSince!) > hiddenLimit { NSApp.terminate(nil) }
    }
  }

  // Is Zed's focused window showing a .typ file? nil when we can't tell.
  func zedShowsTypst() -> Bool? {
    guard AXIsProcessTrusted(),
      let zed = NSRunningApplication.runningApplications(withBundleIdentifier: zedBundle).first
    else { return nil }
    let app = AXUIElementCreateApplication(zed.processIdentifier)
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
      let win = focused
    else { return nil }
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title)
    // titles look like "project — file.typ"
    return (title as? String)?.hasSuffix(".typ") ?? false
  }

  func checkServer() {
    var req = URLRequest(url: target)
    req.httpMethod = "HEAD"
    req.timeoutInterval = 1
    URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        if response == nil {
          self.offline += 1
          if self.offline >= offlineLimit { NSApp.terminate(nil) }
        } else {
          self.offline = 0
        }
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
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { webView.load(URLRequest(url: target)) }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon or menu bar
app.run()
