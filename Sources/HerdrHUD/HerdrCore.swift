import Foundation

/// What the HUD needs from a Herdr transport: a roster, one agent's recent output, and one checked prompt.
protocol HUDBackend: AnyObject {
    func snapshot() -> Row
    func output(_ id: String) throws -> Row
    func prompt(_ id: String, _ message: String) throws -> Row
}
extension HerdrClient: HUDBackend {}

/// Herdr Desktop / herdr-core backend. Speaks JSON-RPC 2.0 to `hc connect` over stdin/stdout, so prompt text never
/// appears in argv, and resolves Space and Tab names from the core document `herdr-app`, which Herdr Desktop keeps
/// in the core even while its window is closed. Connected machines arrive multiplexed as `machine/t7`.
final class CoreHerdrClient: HUDBackend {
    static let candidates = [NSHomeDirectory() + "/.local/bin/hc", "/opt/homebrew/bin/hc", "/usr/local/bin/hc"]
    static let readyStates = ["idle", "done"]
    /// What a send is checked against: the exact terminal (address + creation time), its program, and its Space.
    struct Binding: Equatable { let machine: String, address: String, created: String, provider: String, workspace: String }
    let connect: () throws -> CoreChannel
    let installed: Bool
    let readTimeout: TimeInterval, sendTimeout: TimeInterval
    var cache: [String: [Row]] = [:], labels: [String: String] = [:]
    var bindings: [String: Binding] = [:]
    init(binary: String? = nil, connect: (() throws -> CoreChannel)? = nil, readTimeout: TimeInterval = 12, sendTimeout: TimeInterval = 75) {
        let found = binary ?? Self.candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        installed = connect != nil || found != nil
        let executable = found ?? "/usr/bin/env"
        self.connect = connect ?? { try RPCPipe(executable: executable, arguments: (executable == "/usr/bin/env" ? ["hc"] : []) + ["connect"]) }
        self.readTimeout = readTimeout; self.sendTimeout = sendTimeout
    }

    // MARK: Roster

    struct Place { let space: Row, tab: Row, pane: String }
    /// Bare terminal address ("t7") → its Space, Tab and pane in a `herdr-app` document.
    static func layout(_ document: Any?) -> [String: Place] {
        var found: [String: Place] = [:]
        func walk(_ node: Row, _ space: Row, _ tab: Row, _ depth: Int) {
            guard depth < 64 else { return }
            if node["type"] as? String == "block", let terminal = (node["content"] as? Row)?["terminal"] as? String, found[terminal] == nil {
                found[terminal] = Place(space: space, tab: tab, pane: node["id"] as? String ?? terminal)
            }
            for child in node["children"] as? [Row] ?? [] { walk(child, space, tab, depth + 1) }
        }
        for space in ((document as? Row)?["value"] as? Row)?["spaces"] as? [Row] ?? [] {
            for tab in space["tabs"] as? [Row] ?? [] { if let root = tab["root"] as? Row { walk(root, space, tab, 0) } }
        }
        return found
    }
    static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    /// A window title without the spinner or status glyphs programs put in front of it.
    static func cleanTitle(_ value: Any?) -> String? {
        guard let title = text(value) else { return nil }
        return text(String(title.drop(while: { !$0.isLetter && !$0.isNumber })))
    }
    static func command(_ argv: Any?) -> String? { text(((argv as? [String])?.first).map { ($0 as NSString).lastPathComponent }) }
    /// The program as bound for identity and the replacement check: the program's own 7501 `app` word, else the
    /// command the terminal was launched with. Both stay fixed for a terminal's life. `foreground.argv` does not:
    /// it follows whatever runs in front (an agent's tool, a pager), so it never enters ids or checks.
    static func program(_ t: Row) -> String { text((t["status"] as? Row)?["app"]) ?? command(t["argv"]) ?? "" }
    /// The program as shown: like `program`, but a terminal without an `app` word shows its foreground command
    /// (`codex` rather than the launching shell), which also selects the interface's Chat view.
    static func shownProgram(_ t: Row) -> String {
        text((t["status"] as? Row)?["app"]) ?? command((t["foreground"] as? Row)?["argv"]) ?? command(t["argv"]) ?? ""
    }
    static func status(_ t: Row) -> String {
        switch (t["status"] as? Row)?["state"] as? String {
        case "idle": return "idle"
        case "working": return "working"
        case "done": return "done"
        case "blocked", "error": return "blocked"
        default: return "unknown"
        }
    }
    static func isAgent(_ t: Row) -> Bool { t["state"] as? String == "live" && (t["reported"] as? Bool == true || t["status"] is Row) }
    /// `created_ms` as an exact decimal string, so the replacement check never goes through floating point.
    static func created(_ t: Row) -> String { (t["created_ms"] as? NSNumber)?.stringValue ?? "" }
    static func workspaceKey(_ t: Row) -> String { text((t["labels"] as? Row)?["herdr.space"]) ?? (t["cwd"] as? String ?? "") }
    /// The HUD id. It uses a `core:` prefix that cannot collide with TUI JSON-array keys (even for a TUI machine
    /// whose id is `"core"`), and never contains `turn` or status so alerts fire across turns.
    static func identity(machine: String, address: String, created: String, provider: String) -> String {
        "core:" + encode([machine, address, created, provider])
    }
    static func folderLabel(_ path: String?, home: String) -> String? {
        guard let path = text(path) else { return nil }
        if path == home || path == "~" { return "~" }
        return text((path as NSString).lastPathComponent)
    }
    /// One terminal as a HUD agent row, in the shape the shared interface and Shepherdr linking expect.
    static func agent(_ t: Row, machine: String, label: String, place: Place?, home: String) -> Row {
        let address = t["address"] as? String ?? "", labels = t["labels"] as? Row ?? [:], provider = program(t), shown = shownProgram(t), stamp = created(t)
        let status = t["status"] as? Row ?? [:]
        let tabName = text(place?.tab["name"])
        let numeric = tabName.map { $0.allSatisfy(\.isNumber) } ?? true
        let tabLabel = (numeric ? nil : tabName) ?? text(t["name"]) ?? cleanTitle(status["title"]) ?? cleanTitle(t["title"]) ?? text(shown) ?? tabName ?? address
        return ["id": identity(machine: machine, address: address, created: stamp, provider: provider),
                "address": address,
                "terminal_id": "\(address)@\(stamp)",
                "agent_session": NSNull(),
                "agent": shown,
                "agent_status": Self.status(t),
                "workspace_id": text(place?.space["id"]) ?? text(labels["herdr.space"]) ?? (t["cwd"] as? String ?? ""),
                "workspace_label": text(place?.space["name"]) ?? folderLabel((place?.space["folder"] as? String) ?? (t["cwd"] as? String), home: home) ?? "Standalone",
                "tab_id": text(place?.tab["id"]) ?? text(labels["herdr.tab"]) ?? address,
                "tab_label": tabLabel,
                "pane_id": place?.pane ?? address,
                "name": text(t["name"]) ?? tabLabel,
                "machine_id": machine, "machine_label": label, "online": true]
    }
    /// The whole roster from one `hc connect`. Throws only when the core itself cannot be reached.
    func fetch() throws -> Row {
        let channel = try connect()
        defer { channel.close() }
        let deadline = Date().addingTimeInterval(readTimeout)
        func call(_ method: String, _ params: Row = [:]) throws -> Any {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { throw HUDError("Herdr core timed out.") }
            return try channel.call(method, params, timeout: left)
        }
        let hello = try call("hello") as? Row ?? [:]
        guard let list = try call("terminal.list") as? Row, let terminals = list["terminals"] as? [Row] else { throw HUDError("Herdr core returned an unsupported roster format.") }
        let views = (list["machines"] as? [Row] ?? []).filter { $0["temporary"] as? Bool != true && $0["name"] is String }
        let temporary = Set((list["machines"] as? [Row] ?? []).filter { $0["temporary"] as? Bool == true }.compactMap { $0["name"] as? String })
        let localLabel = Host.current().localizedName ?? (((hello["core"] as? Row)?["name"] as? String) ?? "This Mac")
        // A missing herdr-app document (Herdr Desktop never ran) only costs the Space and Tab names.
        var layouts: [String: [String: Place]] = ["local": Self.layout(try? call("doc.get", ["name": "herdr-app"]))]
        for view in views where view["state"] as? String == "connected" {
            let name = view["name"] as! String
            layouts[name] = Self.layout(try? call("doc.get", ["name": "herdr-app", "on": name]))
        }
        var agents: [Row] = [], states: [Row] = [], next: [String: Binding] = [:], rows: [String: [Row]] = ["local": []]
        for view in views where view["state"] as? String == "connected" { rows[view["name"] as! String] = [] }
        for t in terminals where Self.isAgent(t) {
            guard let address = t["address"] as? String, !address.isEmpty else { continue }
            let parts = address.split(separator: "/", maxSplits: 1).map(String.init)
            let machine = parts.count == 2 ? parts[0] : "local", bare = parts.count == 2 ? parts[1] : address
            guard !temporary.contains(machine), rows[machine] != nil else { continue }
            let home = machine == "local" ? NSHomeDirectory() : ""
            let row = Self.agent(t, machine: machine, label: machine == "local" ? localLabel : machine, place: layouts[machine]?[bare], home: home)
            next[row["id"] as! String] = Binding(machine: machine, address: address, created: Self.created(t), provider: Self.program(t), workspace: Self.workspaceKey(t))
            rows[machine]!.append(row)
        }
        agents += rows["local"]!; states.append(["id": "local", "label": localLabel, "session": "default", "online": true, "count": rows["local"]!.count])
        cache["local"] = rows["local"]; labels["local"] = localLabel
        for view in views {
            let name = view["name"] as! String
            labels[name] = name
            if let live = rows[name] {
                cache[name] = live; agents += live
                states.append(["id": name, "label": name, "session": view["session"] as? String ?? "default", "online": true, "count": live.count])
            } else {
                // Not connected: keep its last cards visible, but read-only (no binding means no send).
                agents += (cache[name] ?? []).map { $0.merging(["online": false], uniquingKeysWith: { _, b in b }) }
                states.append(["id": name, "label": name, "session": view["session"] as? String ?? "default", "online": false, "error": Self.text(view["why"]) ?? (view["state"] as? String ?? "offline")])
            }
        }
        let known = Set(views.map { $0["name"] as! String } + ["local"])
        cache = cache.filter { known.contains($0.key) }; labels = labels.filter { known.contains($0.key) }
        bindings = next
        return ["agents": agents, "machines": states, "discoveryError": "", "backend": "core"]
    }
    /// The roster, or when the core is unreachable every last-known card offline and nothing sendable.
    func snapshot() -> Row {
        do { return try fetch() } catch { return offline(error.localizedDescription) }
    }
    func offline(_ message: String) -> Row {
        bindings = [:]
        if cache.isEmpty { cache["local"] = []; labels["local"] = Host.current().localizedName ?? "This Mac" }
        let order = ["local"] + cache.keys.filter { $0 != "local" }.sorted()
        let agents = order.flatMap { (cache[$0] ?? []).map { $0.merging(["online": false], uniquingKeysWith: { _, b in b }) } }
        let states: [Row] = order.map { ["id": $0, "label": labels[$0] ?? $0, "session": "default", "online": false, "error": message] }
        return ["agents": agents, "machines": states, "discoveryError": message, "backend": "core"]
    }

    // MARK: Output and prompt

    /// Re-reads the bound terminal and refuses anything that is not the same live terminal, program and Space.
    func verify(_ binding: Binding, _ current: Any) throws -> Row {
        guard let t = current as? Row, t["state"] as? String == "live", t["address"] as? String == binding.address || (t["address"] as? String).map({ binding.address.hasSuffix("/" + $0) }) == true,
              Self.created(t) == binding.created, Self.program(t) == binding.provider, Self.workspaceKey(t) == binding.workspace
        else { throw HUDError("The selected agent was replaced. Select its new session.") }
        return t
    }
    func output(_ id: String) throws -> Row {
        guard let binding = bindings[id] else { throw HUDError("Agent is offline or changed. Refresh and select it again.") }
        let channel = try connect()
        defer { channel.close() }
        let deadline = Date().addingTimeInterval(readTimeout)
        let current = try verify(binding, try channel.call("terminal.get", ["terminal": binding.address], timeout: readTimeout))
        let read = try channel.call("terminal.read", ["terminal": binding.address, "lines": 180], timeout: max(0.1, deadline.timeIntervalSinceNow)) as? Row
        guard let text = read?["text"] as? String else { throw HUDError("Herdr core returned unreadable output.") }
        return ["id": id, "provider": Self.shownProgram(current), "text": text]
    }
    /// Two turns over one `hc connect`: (1) `terminal.get` proves the same live terminal is ready, and refusing there
    /// sends nothing; (2) `terminal.send` carries the text over stdin. Any doubt in turn 2 is reported as uncertain
    /// and is never retried, because the text may already have been typed.
    func prompt(_ id: String, _ message: String) throws -> Row {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, message.utf8.count <= 60000, !message.contains("\0"), !message.hasPrefix("-") else { throw HUDError("Enter a prompt under 60 KB that does not start with a dash.") }
        guard let binding = bindings[id] else { throw HUDError("Agent is offline or changed. Refresh and select it again.") }
        let channel = try connect()
        defer { channel.close() }
        let current: Row
        do { current = try verify(binding, try channel.call("terminal.get", ["terminal": binding.address], timeout: readTimeout)) }
        catch let error as CoreRPCError { throw HUDError(error.kind == "not_found" || error.kind == "finished" ? "The selected agent was replaced. Select its new session." : "Herdr refused: \(error.message)") }
        let live = (current["status"] as? Row)?["state"] as? String ?? ""
        guard Self.readyStates.contains(live) else { throw HUDError("This agent is busy or needs input. Answer native questions in Herdr.") }
        var params: Row = ["terminal": binding.address, "text": message, "force": false]
        if live == "idle" { params["if"] = "idle" }  // `if` accepts only idle or working; done has no guard word
        let reply: Any
        do { reply = try channel.call("terminal.send", params, timeout: sendTimeout) }
        catch { throw HUDError("Delivery uncertain. Inspect Herdr before sending again.") }
        guard let result = reply as? Row, result["turn"] is NSNumber else { throw HUDError("Delivery uncertain. Inspect Herdr before sending again.") }
        return ["ok": true, "id": id]
    }
}

extension HerdrClient { var installed: Bool { binary != "/usr/bin/env" } }

/// Chooses the transport. `backendMode`: "core" (Herdr Desktop / hc), "tui" (herdr CLI), or "auto": the core when
/// `hc` is installed and answers with agents, otherwise the herdr CLI. `hc connect` starts a core on demand, so an
/// empty core next to an installed herdr CLI is not evidence the user works in the core: the CLI is asked too. Reads and sends follow the id's own backend, so a prompt
/// can never be routed to a different transport than the roster entry it was chosen from.
final class BackendRouter: HUDBackend {
    enum Mode: String, CaseIterable { case auto, core, tui }
    let core: CoreHerdrClient, tui: HerdrClient
    let defaults: UserDefaults
    let forced: Mode?
    init(core: CoreHerdrClient = CoreHerdrClient(), tui: HerdrClient = HerdrClient(), defaults: UserDefaults = .standard, mode: Mode? = nil) {
        self.core = core; self.tui = tui; self.defaults = defaults; forced = mode
    }
    var mode: Mode { forced ?? Mode(rawValue: defaults.string(forKey: "backendMode") ?? "") ?? .auto }
    static func isCore(_ id: String) -> Bool { id.hasPrefix("core:") }
    /// Upgrades a pre-prefix 5-element Core key `["core", machine, address, created, provider]` to `core:[...]`,
    /// leaving 6-element TUI keys (including a TUI saved machine whose id is literally `"core"`) untouched.
    static func migrateSelection(_ id: String) -> String {
        guard id.hasPrefix("[\"core\","), let data = id.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count == 5, array[0] as? String == "core", array.dropFirst().allSatisfy({ $0 is String })
        else { return id }
        return "core:" + encode(Array(array.dropFirst()))
    }
    static func hasOnlineAgent(_ roster: Row) -> Bool {
        (roster["agents"] as? [Row] ?? []).contains { $0["online"] as? Bool == true }
    }
    /// Whether a saved selection can still name an agent after the user picks `mode`. Shepherdr views and Automatic
    /// (which may land on either backend) keep it; an explicit backend drops the other backend's ids.
    static func selectionSurvives(_ id: String, after mode: Mode) -> Bool {
        let current = migrateSelection(id)
        if current.isEmpty || current.hasPrefix("shepherdr:") { return true }
        switch mode { case .auto: return true; case .core: return isCore(current); case .tui: return !isCore(current) }
    }
    func snapshot() -> Row {
        switch mode {
        case .core: tui.bindings = [:]; return core.snapshot()
        case .tui: core.bindings = [:]; return tui.snapshot().merging(["backend": "tui"], uniquingKeysWith: { _, b in b })
        case .auto:
            if core.installed, let roster = try? core.fetch() {
                guard !Self.hasOnlineAgent(roster), tui.installed else { tui.bindings = [:]; return roster }
                let other = tui.snapshot()
                if Self.hasOnlineAgent(other) || ((roster["agents"] as? [Row] ?? []).isEmpty && !(other["agents"] as? [Row] ?? []).isEmpty) {
                    core.bindings = [:]; return other.merging(["backend": "tui"], uniquingKeysWith: { _, b in b })
                }
                tui.bindings = [:]; return roster
            }
            core.bindings = [:]
            return tui.snapshot().merging(["backend": "tui"], uniquingKeysWith: { _, b in b })
        }
    }
    func output(_ id: String) throws -> Row { let key = Self.migrateSelection(id); return Self.isCore(key) ? try core.output(key) : try tui.output(key) }
    func prompt(_ id: String, _ message: String) throws -> Row { let key = Self.migrateSelection(id); return Self.isCore(key) ? try core.prompt(key, message) : try tui.prompt(key, message) }
}
