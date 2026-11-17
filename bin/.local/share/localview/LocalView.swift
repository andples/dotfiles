// LocalView: a borderless pane showing one local web page (tinymist's Typst preview)
// beside Zed, and nothing else: no title bar, tabs, address bar, Dock icon, menus or
// app-switcher entry. `typview` builds and opens it.
//
//   LocalView URL
//
// It belongs to the Zed window it was opened from: it floats beside that window only while
// Zed is the active app, that window is in front, and its active tab is a .typ file. Other
// Zed windows, other tabs and other apps hide it. Clicking it doesn't take focus from Zed, so
// click-to-jump lands you back in the editor. It quits after a minute of Zed showing
// other files (you closed the Typst file), when Zed quits, or when the preview server is
// gone for 10 seconds.
//
// `typview` again (SIGUSR1): from the same window it closes; from another Zed window it
// moves there. On launch it splits Zed's front window: Zed keeps the left half,
// the pane takes the right. If Zed's window is already narrow, the pane fills the space
// beside it instead. Needs LocalView in System Settings > Privacy > Accessibility (asked
// once) to see and resize Zed's window. While the pane shows, Zed is kept to the space
// beside it.
//
// A small menu bar icon shows it's running (hollow while the server is gone); its menu
// closes or reloads the preview. Closing it (Cmd-W, `typview` again, or quitting on its own)
// widens Zed's window back to the edge of the screen.
//
// It takes Zed's current theme: the space around the pages and the pages themselves use
// the theme's editor background and text colours (rechecked every second, so switching
// theme carries over), and scrolling stops at the edges instead of bouncing into grey.
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
  var besideZed: AXUIElement?  // the Zed window the pane sits beside, widened again on close
  var status: NSStatusItem!
  var live = true
  var signals: [DispatchSourceSignal] = []

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
    config.userContentController.addUserScript(
      WKUserScript(source: themeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.allowsMagnification = true
    pane.contentView = web

    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let reload = NSMenuItem(title: "Reload Preview", action: #selector(reloadPreview), keyEquivalent: "")
    reload.target = self
    menu.addItem(reload)
    menu.addItem(NSMenuItem(title: "Close Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    status.menu = menu
    showLive(true)
    web.load(URLRequest(url: target))

    // SIGTERM: close properly, widening Zed back. SIGUSR1 (`typview` again): toggle.
    for (sig, handler) in [(SIGTERM, { NSApp.terminate(nil) }), (SIGUSR1, { [unowned self] in self.toggle() })] {
      signal(sig, SIG_IGN)
      let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      src.setEventHandler(handler: handler)
      src.resume()
      signals.append(src)
    }

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
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
      self.checkServer()
      self.followTheme()
      self.web.evaluateJavaScript("window.__lvEnsure && window.__lvEnsure()")
    }
    followTheme()
  }

  // `space p` again: close from the window it belongs to, move to any other Zed window
  func toggle() {
    if let mine = besideZed, let front = zedWindow(), !CFEqual(mine, front) {
      applicationWillTerminate(Notification(name: .init("move")))  // widen the old window back
      layout()
      update()
    } else {
      NSApp.terminate(nil)
    }
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
    besideZed = win
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

  @objc func reloadPreview() { web.reload() }

  func showLive(_ on: Bool) {
    live = on
    let image = NSImage(
      systemSymbolName: on ? "doc.richtext.fill" : "doc.richtext",
      accessibilityDescription: on ? "Typst preview: live" : "Typst preview: offline")
    image?.isTemplate = true  // follows the menu bar's light/dark look
    status.button?.image = image
    status.button?.toolTip = on ? "Typst live preview" : "Typst live preview (server offline)"
  }

  // Give Zed its full width back
  func applicationWillTerminate(_ note: Notification) {
    guard let win = besideZed, let z = axFrame(win), let primary = NSScreen.screens.first else { return }
    let zed = NSRect(x: z.minX, y: primary.frame.height - z.maxY, width: z.width, height: z.height)
    let screen = NSScreen.screens.first { $0.frame.intersects(zed) } ?? primary
    axSetWidth(win, z, screen.visibleFrame.maxX - z.minX)
  }

  // Is the frontmost ordinary window Zed's? Menu bar menus, status item popovers, Spotlight
  // and the like sit above ordinary windows, so opening them (even when it makes their app
  // active) doesn't hide the pane; focusing another app's window does.
  func zedWindowInFront() -> Bool {
    let me = ProcessInfo.processInfo.processIdentifier
    let zed = zedApp()?.processIdentifier
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return true }
    for w in list {  // front to back
      guard (w[kCGWindowLayer as String] as? Int) == 0,
            let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me else { continue }
      if let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) < 50 || (b["Height"] ?? 0) < 50 {
        continue  // invisible helper windows
      }
      return pid == zed
    }
    return false
  }

  func update() {
    // Accessibility granted while running: move beside Zed now
    if !placedBesideZed && AXIsProcessTrusted() { layout() }
    let zedActive = zedWindowInFront()
    // the window it belongs to is in front, on a Typst tab (without Accessibility we can't
    // tell: assume yes)
    var typst = true
    if let front = zedWindow() {
      let mine = besideZed.map { CFEqual($0, front) } ?? true
      typst = mine && (axTitle(front)?.hasSuffix(".typ") ?? false)
    }

    if zedActive && typst {
      if !pane.isVisible { pane.orderFrontRegardless() }
      keepZedBeside()
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

  // While showing, Zed's right edge stays against the pane: shrink it if it grew over the
  // pane (Zed resizing itself, a maximise), widen it if a gap opened
  func keepZedBeside() {
    guard let win = besideZed, let z = axFrame(win) else { return }
    // the pane's top and bottom follow Zed's window (it may still have been opening, or
    // since moved or resized, when the pane was placed)
    if let primary = NSScreen.screens.first {
      let y = primary.frame.height - z.maxY
      if abs(pane.frame.minY - y) > 1 || abs(pane.frame.height - z.height) > 1 {
        pane.setFrame(NSRect(x: pane.frame.minX, y: y, width: pane.frame.width, height: z.height), display: true)
      }
    }
    let edge = pane.frame.minX  // x means the same in AX and AppKit coordinates
    guard z.minX < edge - 200, abs(z.maxX - edge) > 2 else { return }
    axSetWidth(win, z, edge - z.minX)
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
        if (self.offline == 0) != self.live { self.showLive(self.offline == 0) }
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
  // ── Zed's theme ──
  var theme: (bg: String, fg: String)?
  var themeStamp = ""

  func followTheme() {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path
    let settings = home + "/.config/zed/settings.json"
    let themeDirs = [home + "/.config/zed/themes"]
      + ((try? fm.contentsOfDirectory(atPath: home + "/Library/Application Support/Zed/extensions/installed")) ?? [])
      .map { home + "/Library/Application Support/Zed/extensions/installed/" + $0 + "/themes" }
    let files = [settings] + themeDirs.flatMap { d in
      ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".json") }.map { d + "/" + $0 }
    }
    let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    // only re-read when a file or the system appearance changed
    let stamp = files.map { f in
      "\((try? fm.attributesOfItem(atPath: f)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }.joined(separator: ",") + "\(dark)"
    if stamp == themeStamp { return }
    themeStamp = stamp

    var name: String?
    if let text = try? String(contentsOfFile: settings, encoding: .utf8) {
      // "theme": "Name"  or  "theme": { "mode": "...", "light": "...", "dark": "..." }
      if let plain = capture(#""theme"\s*:\s*"([^"]+)""#, text) {
        name = plain
      } else if let obj = capture(#""theme"\s*:\s*\{([^}]*)\}"#, text) {
        let mode = capture(#""mode"\s*:\s*"([^"]+)""#, obj) ?? "system"
        let key = mode == "dark" || (mode == "system" && dark) ? "dark" : "light"
        name = capture(#"""# + key + #""\s*:\s*"([^"]+)""#, obj)
      }
    }
    var found: (bg: String, fg: String)?
    for f in files.dropFirst() {
      guard let data = fm.contents(atPath: f),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let themes = json["themes"] as? [[String: Any]]
      else { continue }
      for t in themes where t["name"] as? String == name {
        let style = t["style"] as? [String: Any] ?? [:]
        if let bg = style["editor.background"] as? String,
          let fg = (style["editor.foreground"] ?? style["text"]) as? String
        {
          found = (String(bg.prefix(7)), String(fg.prefix(7)))
        }
      }
    }
    // a built-in theme (no file to read): plain colours for the system appearance
    theme = found ?? (dark ? ("#1e1f22", "#d6d6d6") : ("#ffffff", "#1a1a1a"))
    applyTheme()
  }

  func applyTheme() {
    guard let t = theme else { return }
    pane.backgroundColor = NSColor(hex: t.bg) ?? .windowBackgroundColor
    web.evaluateJavaScript(
      "window.__lvColors = ['\(t.bg)', '\(t.fg)']; window.__lvTheme && window.__lvTheme('\(t.bg)', '\(t.fg)')")
  }

  func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) { applyTheme() }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { webView.load(URLRequest(url: target)) }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

// Recolours the preview: page white becomes the theme background, black the theme text
// (a per-channel linear map, like the preview's own dark-mode invert but to exact colours)
let themeScript = """
window.__lvTheme = function (bg, fg) {
  window.__lvColors = [bg, fg];
  const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  const [b, f] = [rgb(bg), rgb(fg)];
  const ns = 'http://www.w3.org/2000/svg';
  let svg = document.getElementById('lv-defs');
  if (!svg) {
    svg = document.createElementNS(ns, 'svg');
    svg.id = 'lv-defs';
    svg.setAttribute('style', 'position:absolute;width:0;height:0');
    svg.innerHTML = '<filter id="lv-theme" color-interpolation-filters="sRGB"><feComponentTransfer>'
      + '<feFuncR type="linear"/><feFuncG type="linear"/><feFuncB type="linear"/></feComponentTransfer></filter>';
    document.body.appendChild(svg);
  }
  const fns = svg.querySelectorAll('feFuncR, feFuncG, feFuncB');
  fns.forEach((fn, i) => { fn.setAttribute('slope', b[i] - f[i]); fn.setAttribute('intercept', f[i]); });
  let st = document.getElementById('lv-style');
  if (!st) { st = document.createElement('style'); st.id = 'lv-style'; document.head.appendChild(st); }
  st.textContent = `
    :root { --typst-preview-background-color: ${bg} !important; }
    html, body, #typst-container, #typst-container-main, #typst-app { background: ${bg} !important; }
    html, body, #typst-container-main { overscroll-behavior: none !important; }
    .typst-doc, canvas { filter: url(#lv-theme); }`;
};
// re-apply if the preview rebuilt the page (checked every second by LocalView)
window.__lvEnsure = function () {
  if (window.__lvColors && !(document.getElementById('lv-style') && document.getElementById('lv-defs'))) {
    window.__lvTheme(...window.__lvColors);
  }
};
// colours LocalView set before this script was injected
if (window.__lvColors) window.__lvTheme(...window.__lvColors);
"""

// First capture group of a regex match, or nil
func capture(_ pattern: String, _ text: String) -> String? {
  guard let re = try? NSRegularExpression(pattern: pattern),
    let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
    let r = Range(m.range(at: 1), in: text)
  else { return nil }
  return String(text[r])
}

extension NSColor {
  convenience init?(hex: String) {
    guard hex.count >= 7, let v = UInt32(hex.dropFirst().prefix(6), radix: 16) else { return nil }
    self.init(
      srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
      blue: CGFloat(v & 0xff) / 255, alpha: 1)
  }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon, menu bar or Cmd-Tab entry
app.run()
