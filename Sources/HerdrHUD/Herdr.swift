import Foundation
import Darwin

typealias Row = [String: Any]
struct HUDError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
func encode(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]), let text = String(data: data, encoding: .utf8) else { return "null" }
    return text
}
func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
struct Machine: Equatable {
    let id: String, label: String, target: String?, session: String
    var json: Row { ["id": id, "label": label, "session": session] }
}
struct Invocation {
    let executable: String
    let arguments: [String]
    let mutation: Bool
    var input: Data? = nil
    var localPrompt: Bool = false
}
final class HerdrClient {
    let execute: (Invocation) throws -> String
    let binary: String
    var cache: [String: [Row]] = [:]
    var bindings: [String: (Machine, Row)] = [:]
    var machines: [Machine] = []
    var discoveryError = ""
    init(binary: String? = nil, execute: ((Invocation) throws -> String)? = nil) {
        let candidates = [NSHomeDirectory() + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        self.binary = binary ?? candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/env"
        let runner = ProcessRunner()
        self.execute = execute ?? { try runner.run($0) }
    }
    func invocation(_ machine: Machine, _ args: [String], mutation: Bool = false, input: Data? = nil) throws -> Invocation {
        let scoped = ["--session", machine.session] + args
        guard !scoped.contains(where: { $0.contains("\0") }) else { throw HUDError("Invalid command argument.") }
        if let target = machine.target {
            guard !target.isEmpty, !target.hasPrefix("-"), !target.contains(where: { $0.isWhitespace || $0.isNewline }), !target.contains("\0") else { throw HUDError("Invalid saved SSH target.") }
            // The remote login shell may be fish. Run our fixed POSIX script explicitly.
            // Herdr's standard user install is checked first, then normal PATH lookup.
            let script = "unset HERDR_ENV HERDR_SOCKET_PATH HERDR_CONFIG_PATH HERDR_SESSION HERDR_SESSION_NAME HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_PANE_ID HERDR_TERMINAL_ID; if [ -x \"$HOME/.local/bin/herdr\" ]; then exec \"$HOME/.local/bin/herdr\" \"$@\"; elif [ -x /opt/homebrew/bin/herdr ]; then exec /opt/homebrew/bin/herdr \"$@\"; else exec herdr \"$@\"; fi"
            let remote = mutation ? ["python3", "-c", try String(contentsOf:HUDResources.root.appendingPathComponent("prompt.py"),encoding:.utf8)].map(shellQuote).joined(separator:" ") : (["sh", "-c", script, "herdr-hud"] + scoped).map(shellQuote).joined(separator: " ")
            return Invocation(executable: "/usr/bin/ssh", arguments: ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=yes", target, remote], mutation: mutation, input: input)
        }
        return Invocation(executable: binary, arguments: (binary == "/usr/bin/env" ? ["herdr"] : []) + scoped, mutation: mutation, input:input, localPrompt:mutation)
    }
    func call(_ machine: Machine, _ args: [String], mutation: Bool = false) throws -> String {
        try execute(invocation(machine, args, mutation: mutation))
    }
    func rows(_ machine: Machine, _ group: String) throws -> [Row] {
        let raw = try call(machine, [group, "list"])
        guard let data = raw.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? Row,
              let result = object["result"] as? Row,
              let rows = result[["agent":"agents", "workspace":"workspaces", "tab":"tabs"][group]!] as? [Row] else { throw HUDError("Herdr returned an unsupported roster format.") }
        return rows
    }
    func discover() throws -> [Machine] {
        let local = Machine(id: "local", label: Host.current().localizedName ?? "This Mac", target: nil, session: "default")
        let raw = try call(local, ["machine", "list", "--json"])
        guard let data = raw.data(using: .utf8), let saved = try JSONSerialization.jsonObject(with: data) as? [Row] else { throw HUDError("Cannot read Herdr's saved machines.") }
        var found = [local], seen = Set(["local"])
        for row in saved where row["enabled"] as? Bool == true {
            guard let id = row["id"] as? String, let target = row["target"] as? String, !seen.contains(id) else { continue }
            seen.insert(id)
            found.append(Machine(id: id, label: row["label"] as? String ?? target, target: target, session: row["session"] as? String ?? "default"))
        }
        return found
    }
    static func key(_ machine: Machine, _ row: Row) -> String {
        encode([machine.id, machine.target ?? "", machine.session, row["pane_id"] ?? "", row["terminal_id"] ?? "", row["agent_session"] ?? NSNull()])
    }
    func snapshot() -> Row {
        do { machines = try discover(); discoveryError = "" }
        catch { discoveryError = error.localizedDescription; if machines.isEmpty { machines = [Machine(id:"local", label:"This Mac", target:nil, session:"default")] } }
        var all: [Row] = [], states: [Row] = [], nextBindings: [String: (Machine, Row)] = [:]
        for machine in machines {
            do {
                let agents = try rows(machine, "agent"), spaces = try rows(machine, "workspace"), tabs = try rows(machine, "tab")
                let enriched = agents.map { original -> Row in
                    var row = original
                    row["id"] = Self.key(machine, row)
                    row["machine_label"] = machine.label; row["machine_id"] = machine.id; row["online"] = true
                    row["workspace_label"] = spaces.first(where: { ($0["workspace_id"] as? String) == (row["workspace_id"] as? String) })?["label"] ?? row["workspace_id"]
                    row["tab_label"] = tabs.first(where: { ($0["tab_id"] as? String) == (row["tab_id"] as? String) })?["label"] ?? row["tab_id"]
                    nextBindings[row["id"] as! String] = (machine, original)
                    return row
                }
                cache[machine.id] = enriched; all += enriched
                states.append(machine.json.merging(["online": true, "count": enriched.count], uniquingKeysWith: { _, b in b }))
            } catch {
                all += (cache[machine.id] ?? []).map { $0.merging(["online":false], uniquingKeysWith: { _, b in b }) }
                states.append(machine.json.merging(["online": false, "error": error.localizedDescription], uniquingKeysWith: { _, b in b }))
            }
        }
        bindings = nextBindings
        cache = cache.filter { id, _ in machines.contains(where: { $0.id == id }) }
        return ["agents":all, "machines":states, "discoveryError":discoveryError]
    }
    func resolve(_ id: String) throws -> (Machine, Row) {
        guard let (machine, expected) = bindings[id] else { throw HUDError("Agent is offline or changed. Refresh and select it again.") }
        let currentMachines = try discover()
        guard currentMachines.contains(machine) else { throw HUDError("This machine's Herdr configuration changed. Refresh before sending.") }
        guard let current = try rows(machine, "agent").first(where: { ($0["pane_id"] as? String) == (expected["pane_id"] as? String) }),
              Self.key(machine, current) == id,
              (current["workspace_id"] as? String) == (expected["workspace_id"] as? String),
              (current["agent"] as? String) == (expected["agent"] as? String) else { throw HUDError("The selected agent was replaced. Select its new session.") }
        return (machine, current)
    }
    func output(_ id: String) throws -> Row {
        let (machine, row) = try resolve(id)
        return ["id":id, "provider":row["agent"] ?? "", "text":try call(machine, ["agent", "read", row["pane_id"] as! String, "--source", "recent-unwrapped", "--lines", "180"])]
    }
    func prompt(_ id: String, _ message: String) throws -> Row {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, message.utf8.count <= 60000, !message.contains("\0"), !message.hasPrefix("-") else { throw HUDError("Enter a prompt under 60 KB that does not start with a dash.") }
        let (machine, row) = try resolve(id)
        guard ["idle", "done"].contains(row["agent_status"] as? String ?? "") else { throw HUDError("This agent is busy or needs input. Answer native questions in Herdr.") }
        let input=Data((encode(["session":machine.session,"agent":row,"text":message])+"\n").utf8)
        let raw: String
        do { raw = try execute(invocation(machine, ["status","server"], mutation:true, input:input)) }
        catch { throw HUDError("Delivery uncertain or refused. Inspect Herdr before sending again.") }
        guard let data = raw.data(using: .utf8), let response = try? JSONSerialization.jsonObject(with:data) as? Row, (response["result"] as? Row)?["type"] as? String == "agent_prompted", ((response["result"] as? Row)?["agent"] as? Row)?["terminal_id"] as? String == row["terminal_id"] as? String, response["error"] == nil else { throw HUDError("Delivery uncertain. Inspect Herdr before sending again.") }
        return ["ok":true, "id":id]
    }
}
