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

func saveRoute(_ url: String) {
    try? FileManager.default.createDirectory(at: proxyURLFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? url.write(to: proxyURLFile, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: proxyURLFile.path)
}

struct HealConfig { let url: URL; let token: String }

func healConfig() -> HealConfig? {
    let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/muse-vpn/heal.json")
    guard let data = try? Data(contentsOf: file),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let raw = obj["url"] as? String, let url = URL(string: raw),
          let token = obj["token"] as? String else { return nil }
    return HealConfig(url: url, token: token)
}

func healRoute() -> (ok: Bool, message: String) {
    guard let cfg = healConfig() else { return (false, "no repair config installed") }
    var request = URLRequest(url: cfg.url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": cfg.token])
    request.timeoutInterval = 20

    let sem = DispatchSemaphore(value: 0)
    var ok = false
    var message = "repair failed"
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { sem.signal() }
        if let error { message = error.localizedDescription; return }
        guard let http = response as? HTTPURLResponse, let data else { message = "no response"; return }
        ok = http.statusCode == 200
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cidr = obj["cidr"] as? String {
            message = ok ? "repaired for \(cidr)" : "repair failed"
        } else if !ok {
            message = "repair failed (HTTP \(http.statusCode))"
        }
    }.resume()
    _ = sem.wait(timeout: .now() + 25)
    return (ok, message)
}

func isOn() -> Bool { currentProxy() != nil }
func toggle() { setProxy(isOn() ? nil : savedProxyURL()) }

func proxyHost() -> String {
    // Never surface the endpoint address in the UI.
    return currentProxy() == nil ? "no route configured" : "Pantheon Routes"
}

// Runs the bundled setup script with the credentials supplied in the UI.
func runSetup(user: String, pass: String, key: String) -> (ok: Bool, message: String) {
    guard let script = Bundle.main.url(forResource: "setup", withExtension: "py") else {
        return (false, "setup.py is missing from the app bundle")
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = [script.path]
    var env = ProcessInfo.processInfo.environment
    env["MUSE_PROXY_USER"] = user
    env["MUSE_PROXY_PASS"] = pass
    env["META_API_KEY"] = key
    if let route = savedProxyURL() { env["MUSE_ROUTE_URL"] = route }
    proc.environment = env

    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do { try proc.run() } catch {
        return (false, "could not start setup: \(error.localizedDescription)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    if proc.terminationStatus == 0 { return (true, text) }
    return (false, text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(600).description)
}

let args = CommandLine.arguments
if args.contains("--status") { print(isOn() ? "on" : "off"); exit(0) }
if args.contains("--toggle") { toggle(); print(isOn() ? "on" : "off"); exit(0) }
if args.contains("--heal") {
    let result = healRoute()
    print(result.message)
    exit(result.ok ? 0 : 1)
}
if args.contains("--setup") {
    let env = ProcessInfo.processInfo.environment
    guard let u = env["MUSE_PROXY_USER"], let p = env["MUSE_PROXY_PASS"], let k = env["META_API_KEY"] else {
        print("need MUSE_PROXY_USER / MUSE_PROXY_PASS / META_API_KEY")
        exit(2)
    }
    let result = runSetup(user: u, pass: p, key: k)
    print(result.message.trimmingCharacters(in: .whitespacesAndNewlines))
    exit(result.ok ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "o"))
        let setupItem = NSMenuItem(title: "Set Up / Change Key…", action: #selector(showSetup), keyEquivalent: ",")
        setupItem.target = self
        menu.addItem(setupItem)
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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 330),
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

    @objc func showSetup() {
        showWindow()
        webView?.evaluateJavaScript("showSetup();", completionHandler: nil)
    }

    @objc func doToggle() {
        toggle()
        refresh()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }

        switch action {
        case "toggle":
            toggle()
            refresh()
        case "loadConfig":
            guard let text = body["url"] as? String, let url = URL(string: text) else { return }
            DispatchQueue.global().async {
                guard url.scheme == "https" else {
                    DispatchQueue.main.async { self.configResult(ok: false, message: "Config URL must be https.") }
                    return
                }
                do {
                    let data = try Data(contentsOf: url)
                    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let route = obj["route"] as? String,
                          let routeURL = URL(string: route), routeURL.host != nil else {
                        DispatchQueue.main.async { self.configResult(ok: false, message: "Config file must contain {\"route\": \"http://user:pass@host:port\"}.") }
                        return
                    }
                    saveRoute(route)
                    DispatchQueue.main.async {
                        if isOn() { setProxy(route) }
                        self.configResult(ok: true, message: "Route updated.")
                        self.refresh()
                    }
                } catch {
                    DispatchQueue.main.async { self.configResult(ok: false, message: "Download failed: \(error.localizedDescription)") }
                }
            }
        case "heal":
            DispatchQueue.global().async {
                let result = healRoute()
                DispatchQueue.main.async { self.healResult(ok: result.ok, message: result.message) }
            }
        case "setup":
            guard let user = body["user"] as? String, let pass = body["pass"] as? String, let key = body["key"] as? String else { return }
            DispatchQueue.global().async {
                var result = runSetup(user: user, pass: pass, key: key)
                // Self-repair once when the network path looks broken.
                if !result.ok, result.message.lowercased().contains("transport error") || result.message.lowercased().contains("timed out") {
                    let heal = healRoute()
                    if heal.ok { result = runSetup(user: user, pass: pass, key: key) }
                }
                DispatchQueue.main.async {
                    if result.ok {
                        self.setupResult(ok: true, message: "Ready.")
                        self.refresh()
                    } else {
                        self.setupResult(ok: false, message: result.message)
                    }
                }
            }
        default:
            refresh()
        }
    }

    func configResult(ok: Bool, message: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["ok": ok, "message": message]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("configResult(\(json));", completionHandler: nil)
    }

    func healResult(ok: Bool, message: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["ok": ok, "message": message]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("healResult(\(json));", completionHandler: nil)
    }

    func setupResult(ok: Bool, message: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["ok": ok, "message": message]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("setupResult(\(json));", completionHandler: nil)
    }

    func refresh() {
        let on = isOn()
        statusItem.button?.title = on ? "🌐" : "○"
        statusItem.button?.toolTip = on ? "Pantheon Routes: ON" : "Pantheon Routes: OFF (direct)"
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
