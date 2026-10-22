import Cocoa
import WebKit

let home = FileManager.default.homeDirectoryForCurrentUser
let settingsURL = home.appendingPathComponent(".config/muse/settings.json")
let proxyURLFile = home.appendingPathComponent(".config/muse-vpn/proxy-url")

func savedProxyURL() -> String? {
    guard let s = try? String(contentsOf: proxyURLFile, encoding: .utf8) else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

func currentProxy() -> String? {
    guard let data = try? Data(contentsOf: settingsURL),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let transport = obj["endpoint_transport"] as? [String: Any] else { return nil }
    return transport["proxy"] as? String
}

func setProxy(_ value: String?) {
    var obj: [String: Any] = [:]
    if let data = try? Data(contentsOf: settingsURL),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        obj = parsed
    }
    if obj["schema_version"] == nil { obj["schema_version"] = 1 }
    var transport = obj["endpoint_transport"] as? [String: Any] ?? [:]
    if let value { transport["proxy"] = value } else { transport.removeValue(forKey: "proxy") }
    obj["endpoint_transport"] = transport

    try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
        try? out.write(to: settingsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }
}

func isOn() -> Bool { currentProxy() != nil }
func toggle() { setProxy(isOn() ? nil : savedProxyURL()) }
func proxyHost() -> String {
    // Never surface the endpoint address in the UI.
    return currentProxy() == nil ? "no route configured" : "Pantheon Routes"
}

let args = CommandLine.arguments
if args.contains("--status") { print(isOn() ? "on" : "off"); exit(0) }
if args.contains("--toggle") { toggle(); print(isOn() ? "on" : "off"); exit(0) }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "o"))
        toggleItem = NSMenuItem(title: "", action: #selector(doToggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        buildWindow()
        refresh()
        showWindow()
    }

    func buildWindow() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "muse")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pantheon Egress"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView

        if let url = Bundle.main.url(forResource: "ui", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<h1>ui.html missing</h1>", baseURL: nil)
        }
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func doToggle() {
        toggle()
        refresh()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.body as? String {
        case "toggle":
            toggle()
        default:
            break
        }
        refresh()
    }

    func refresh() {
        let on = isOn()
        statusItem.button?.title = on ? "🌐" : "○"
        statusItem.button?.toolTip = on ? "Pantheon: US egress ON" : "Pantheon: US egress OFF (direct)"
        toggleItem?.title = on ? "Turn US egress off" : "Turn US egress on"

        let state: [String: Any] = ["on": on, "host": on ? proxyHost() : ""]
        if let data = try? JSONSerialization.data(withJSONObject: state),
           let json = String(data: data, encoding: .utf8) {
            webView?.evaluateJavaScript("update(\(json));", completionHandler: nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
