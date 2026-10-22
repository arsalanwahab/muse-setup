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

    try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
        try? out.write(to: settingsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }
}

func isOn() -> Bool { currentProxy() != nil }
func toggle() { setProxy(isOn() ? nil : savedProxyURL()) }
func proxyHost() -> String {
    guard let p = currentProxy(), let url = URL(string: p) else { return "no proxy configured" }
    return url.host.map { "\($0):\(url.port ?? 0)" } ?? "no proxy configured"
}

let args = CommandLine.arguments
if args.contains("--status") { print(isOn() ? "on" : "off"); exit(0) }
if args.contains("--toggle") { toggle(); print(isOn() ? "on" : "off"); exit(0) }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!
    var window: NSWindow!
    var statusLabel: NSTextField!
    var hostLabel: NSTextField!
    var toggleButton: NSButton!

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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Muse Egress"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let title = NSTextField(labelWithString: "Muse Egress")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 13)

        hostLabel = NSTextField(labelWithString: "")
        hostLabel.font = .systemFont(ofSize: 11)
        hostLabel.textColor = .secondaryLabelColor

        toggleButton = NSButton(title: "", target: self, action: #selector(doToggle))
        toggleButton.bezelStyle = .rounded

        let quit = NSButton(title: "Quit", target: NSApplication.shared, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded

        let buttons = NSStackView(views: [toggleButton, NSView(), quit])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, statusLabel, hostLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = content
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        statusLabel?.stringValue = on ? "US egress: ON" : "US egress: OFF (direct)"
        statusLabel?.textColor = on ? .systemGreen : .systemOrange
        hostLabel?.stringValue = on ? "via \(proxyHost())" : "muse will call api.meta.ai directly"
        toggleButton?.title = on ? "Turn Off" : "Turn On"
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
