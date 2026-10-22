import Cocoa

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

    let dir = settingsURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
        try? out.write(to: settingsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }
}

func isOn() -> Bool { currentProxy() != nil }

func toggle() {
    setProxy(isOn() ? nil : savedProxyURL())
}

// Headless flags, handy for scripts and for verifying the app.
let args = CommandLine.arguments
if args.contains("--status") {
    print(isOn() ? "on" : "off")
    exit(0)
}
if args.contains("--toggle") {
    toggle()
    print(isOn() ? "on" : "off")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "", action: #selector(doToggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        refresh()
    }

    @objc func doToggle() {
        toggle()
        refresh()
    }

    func refresh() {
        let on = isOn()
        statusItem.button?.title = on ? "🌐" : "○"
        statusItem.button?.toolTip = on ? "Muse: US egress ON" : "Muse: US egress OFF (direct)"
        toggleItem?.title = on ? "Turn US egress off" : "Turn US egress on"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
