import XCTest
import Darwin
@testable import HerdrHUD

/// A scripted core: every request is recorded, and `answer` plays the core's side. No real terminal is ever touched.
final class MockChannel: CoreChannel {
    var calls: [(String, Row)] = []
    let answer: (String, Row) throws -> Any
    init(_ answer: @escaping (String, Row) throws -> Any) { self.answer = answer }
    func call(_ method: String, _ params: Row, timeout: TimeInterval) throws -> Any { calls.append((method, params)); return try answer(method, params) }
    func close() {}
}

final class CoreTransportTests: XCTestCase {
    func terminal(_ address: String = "t7", state: String = "idle", created: Int64 = 1_795_000_000_000, turn: Int = 7, app: String = "codex", space: String = "sp1", live: String = "live") -> Row {
        ["address": address, "created_ms": NSNumber(value: created), "state": live, "reported": true, "turn": turn, "name": NSNull(), "title": "",
         "status": ["app": app, "state": state], "labels": ["herdr.space": space, "herdr.tab": "tb1"], "cwd": "/Users/test", "argv": ["/bin/zsh"]]
    }
    func document(_ terminal: String = "t7", space: String = "Build", tab: String = "Main") -> Row {
        ["value": ["spaces": [["id": "sp1", "name": space, "folder": "/Users/test", "tabs": [["id": "tb1", "name": tab, "root":
            ["type": "row", "id": "tb1", "children": [["type": "block", "id": "pane1", "content": ["terminal": terminal]]]]]]]]], "version": 3]
    }
    /// A core whose terminals and machines can change between calls. `sends` counts terminal.send requests.
    final class Core {
        var terminals: [Row] = [], machines: [Row] = [], docs: [String: Row] = [:], sendReply: () throws -> Any = { ["turn": 8, "status": "idle", "started": true] }
        var channels: [MockChannel] = [], down = false
        var sends: [Row] { channels.flatMap { $0.calls }.filter { $0.0 == "terminal.send" }.map { $0.1 } }
        func connect() throws -> CoreChannel {
            if down { throw HUDError("Could not launch Herdr core (2).") }
            let channel = MockChannel { [unowned self] method, params in
                switch method {
                case "hello": return ["core": ["id": "c1", "name": "testcore"], "version": "0.1.22"]
                case "terminal.list": return ["terminals": self.terminals, "machines": self.machines, "hidden_finished": 0]
                case "doc.get":
                    guard let doc = self.docs[params["on"] as? String ?? "local"] else { throw CoreRPCError(code: -32000, kind: "not_found", message: "no doc") }
                    return doc
                case "terminal.get":
                    guard let t = self.terminals.first(where: { $0["address"] as? String == params["terminal"] as? String }) else { throw CoreRPCError(code: -32000, kind: "not_found", message: "no terminal") }
                    return t
                case "terminal.read": return ["text": "• Actual reply", "complete": true, "how": "history"]
                case "terminal.send": return try self.sendReply()
                default: throw CoreRPCError(code: -32601, kind: "", message: "unknown")
                }
            }
            channels.append(channel); return channel
        }
    }
    func make(_ core: Core) -> CoreHerdrClient { CoreHerdrClient(connect: { try core.connect() }) }
    func onlyID(_ client: CoreHerdrClient) -> String { (client.snapshot()["agents"] as! [Row])[0]["id"] as! String }

    // 1. Prompt text travels over stdin only, never argv, and HC_/HERDR_ variables do not reach the child.
    func testPipeCarriesPromptOverStdinAndStripsEnvironment() throws {
        setenv("HC_TERMINAL_ID", "t99", 1); setenv("HERDR_PANE_ID", "w1:p1", 1)
        defer { unsetenv("HC_TERMINAL_ID"); unsetenv("HERDR_PANE_ID") }
        let script = """
        import json,os,sys
        for line in sys.stdin:
            r=json.loads(line)
            env=sorted(k for k in os.environ if k.startswith(('HC_','HERDR_')))
            print(json.dumps({'jsonrpc':'2.0','id':r['id'],'result':{'text':r['params'].get('text'),'argv':sys.argv,'env':env}}),flush=True)
        """
        let pipe = try RPCPipe(executable: "/usr/bin/python3", arguments: ["-c", script, "connect"])
        defer { pipe.close() }
        let secret = "private 'text' 🐑\n$(touch /tmp/never) `whoami`"
        let result = try pipe.call("terminal.send", ["terminal": "t7", "text": secret], timeout: 5) as! Row
        XCTAssertEqual(result["text"] as? String, secret)
        XCTAssertFalse((result["argv"] as! [String]).joined().contains("private"))
        XCTAssertEqual(result["env"] as? [String], [])
        let second = try pipe.call("terminal.get", ["terminal": "t7"], timeout: 5) as! Row  // one child answers many requests
        XCTAssertEqual(second["argv"] as? [String], ["-c", "connect"])
    }
    func testPipeErrorTimeoutAndChildCleanup() throws {
        let pipe = try RPCPipe(executable: "/usr/bin/python3", arguments: ["-c", "import sys,json\nfor l in sys.stdin:\n r=json.loads(l)\n if r['method']=='x': print(json.dumps({'id':r['id'],'error':{'code':-32000,'message':'nope','data':{'kind':'blocked'}}}),flush=True)"])
        XCTAssertThrowsError(try pipe.call("x", [:], timeout: 5)) { XCTAssertEqual(($0 as? CoreRPCError)?.kind, "blocked") }
        let start = Date()
        XCTAssertThrowsError(try pipe.call("silent", [:], timeout: 0.3)) { XCTAssertTrue($0.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let pid = pipe.pid; pipe.close()
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    // 2. `turn` never enters identity: working → idle on the next turn keeps every identity field, so alerts fire.
    func testIdentityStableAcrossTurns() throws {
        let core = Core(); core.terminals = [terminal(state: "working", turn: 7)]; core.docs["local"] = document()
        let client = make(core)
        let before = (client.snapshot()["agents"] as! [Row])[0]
        core.terminals = [terminal(state: "idle", turn: 8)]
        let after = (client.snapshot()["agents"] as! [Row])[0]
        for key in ["id", "terminal_id"] { XCTAssertEqual(before[key] as? String, after[key] as? String) }
        XCTAssertTrue(before["agent_session"] is NSNull); XCTAssertTrue(after["agent_session"] is NSNull)
        XCTAssertFalse((after["id"] as! String).contains("\"8\"")); XCTAssertEqual(after["terminal_id"] as? String, "t7@1795000000000")
        XCTAssertEqual(before["agent_status"] as? String, "working"); XCTAssertEqual(after["agent_status"] as? String, "idle")
        XCTAssertEqual(after["workspace_label"] as? String, "Build"); XCTAssertEqual(after["tab_label"] as? String, "Main"); XCTAssertEqual(after["pane_id"] as? String, "pane1")
    }

    // 3. A replacement terminal (same address, new created_ms), program or Space is refused before anything is sent.
    func testReplacementRefusedBeforeSend() throws {
        for change in [terminal(created: 1_795_000_000_001), terminal(app: "claude-code"), terminal(space: "sp2"), terminal(live: "finished")] {
            let core = Core(); core.terminals = [terminal()]
            let client = make(core); let id = onlyID(client)
            core.terminals = [change]
            XCTAssertThrowsError(try client.prompt(id, "hello")) { XCTAssertTrue($0.localizedDescription.contains("replaced")) }
            XCTAssertThrowsError(try client.output(id))
            XCTAssertTrue(core.sends.isEmpty)
        }
        let core = Core(); core.terminals = [terminal()]; let client = make(core); let id = onlyID(client)
        core.terminals = []
        XCTAssertThrowsError(try client.prompt(id, "hello")); XCTAssertTrue(core.sends.isEmpty)
    }

    // 4. idle sends with if=idle; done sends without a guard word; working, blocked, error and unknown never send.
    func testReadinessAndIfGuard() throws {
        for (state, guardWord) in [("idle", "idle"), ("done", nil)] as [(String, String?)] {
            let core = Core(); core.terminals = [terminal(state: state)]; let client = make(core)
            XCTAssertEqual(try client.prompt(onlyID(client), "literal $(printf x)\nline")["ok"] as? Bool, true)
            XCTAssertEqual(core.sends.count, 1)
            XCTAssertEqual(core.sends[0]["if"] as? String, guardWord); XCTAssertEqual(core.sends[0]["force"] as? Bool, false)
            XCTAssertEqual(core.sends[0]["text"] as? String, "literal $(printf x)\nline"); XCTAssertEqual(core.sends[0]["terminal"] as? String, "t7")
        }
        for state in ["working", "blocked", "error", "weird"] {
            let core = Core(); core.terminals = [terminal(state: "idle")]; let client = make(core); let id = onlyID(client)
            core.terminals = [terminal(state: state)]
            XCTAssertThrowsError(try client.prompt(id, "hello")); XCTAssertTrue(core.sends.isEmpty)
            XCTAssertEqual((client.snapshot()["agents"] as! [Row])[0]["agent_status"] as? String, ["working": "working", "blocked": "blocked", "error": "blocked"][state] ?? "unknown")
        }
        let core = Core(); core.terminals = [terminal()]; let client = make(core); let id = onlyID(client)
        for text in ["", "  ", "--help", "x\0y", String(repeating: "x", count: 60001)] { XCTAssertThrowsError(try client.prompt(id, text)) }
        XCTAssertTrue(core.sends.isEmpty)
    }

    // 5. Any doubt after terminal.send went out is "uncertain" and is never retried.
    func testUncertainSendNeverRetried() throws {
        let replies: [() throws -> Any] = [{ throw HUDError("Herdr core timed out.") }, { throw CoreRPCError(code: -32000, kind: "status_mismatch", message: "x") }, { ["status": "idle"] }, { "garbage" }]
        for reply in replies {
            let core = Core(); core.terminals = [terminal()]; core.sendReply = reply; let client = make(core)
            XCTAssertThrowsError(try client.prompt(onlyID(client), "hello")) { XCTAssertTrue($0.localizedDescription.contains("uncertain")) }
            XCTAssertEqual(core.sends.count, 1)
        }
    }

    // 6. Remote addresses carry "machine/"; that machine's herdr-app document names the bare "t7".
    func testRemotePrefixMatchesRemoteDocument() throws {
        let core = Core()
        core.machines = [["name": "rohan", "id": "m1", "host": "rohan.lan", "target": "rohan", "version": "0.1.22", "state": "connected"]]
        core.terminals = [terminal("t7"), terminal("rohan/t7", app: "codex")]
        core.docs["local"] = document("t7", space: "Local Space", tab: "Here"); core.docs["rohan"] = document("t7", space: "Remote Space", tab: "There")
        let client = make(core)
        let roster = client.snapshot(), agents = roster["agents"] as! [Row]
        XCTAssertEqual(agents.count, 2)
        let remote = agents.first { $0["machine_id"] as? String == "rohan" }!, local = agents.first { $0["machine_id"] as? String == "local" }!
        XCTAssertEqual(remote["workspace_label"] as? String, "Remote Space"); XCTAssertEqual(remote["tab_label"] as? String, "There")
        XCTAssertEqual(local["workspace_label"] as? String, "Local Space"); XCTAssertNotEqual(remote["id"] as? String, local["id"] as? String)
        XCTAssertTrue(core.channels[0].calls.contains { $0.0 == "doc.get" && $0.1["on"] as? String == "rohan" && $0.1["name"] as? String == "herdr-app" })
        _ = try client.prompt(remote["id"] as! String, "hello")
        XCTAssertEqual(core.sends.last?["terminal"] as? String, "rohan/t7")
    }

    // 7. Temporary machines are left out; a disconnected machine keeps its cards offline and cannot be sent to.
    func testTemporaryAndOfflineMachines() throws {
        let core = Core()
        let rohan: Row = ["name": "rohan", "id": "m1", "host": "rohan", "target": "rohan", "version": "0.1.22", "state": "connected"]
        core.machines = [rohan, ["name": "sandbox", "id": "m2", "host": "sb", "target": "sb", "version": "0.1.22", "state": "connected", "temporary": true]]
        core.terminals = [terminal("t1"), terminal("rohan/t2"), terminal("sandbox/t3"), terminal("t4", live: "finished")]
        let client = make(core)
        var roster = client.snapshot()
        XCTAssertEqual((roster["agents"] as! [Row]).compactMap { $0["address"] as? String }.sorted(), ["rohan/t2", "t1"])
        XCTAssertEqual((roster["machines"] as! [Row]).compactMap { $0["id"] as? String }, ["local", "rohan"])
        let remoteID = (roster["agents"] as! [Row]).first { $0["machine_id"] as? String == "rohan" }!["id"] as! String
        core.machines = [rohan.merging(["state": "unreachable", "why": "ssh: connect timed out"], uniquingKeysWith: { _, b in b })]
        core.terminals = [terminal("t1")]
        roster = client.snapshot()
        let remote = (roster["agents"] as! [Row]).first { $0["machine_id"] as? String == "rohan" }!
        XCTAssertEqual(remote["online"] as? Bool, false)
        XCTAssertEqual((roster["machines"] as! [Row]).first { $0["id"] as? String == "rohan" }?["error"] as? String, "ssh: connect timed out")
        XCTAssertEqual((roster["agents"] as! [Row]).first { $0["machine_id"] as? String == "local" }?["online"] as? Bool, true)
        XCTAssertThrowsError(try client.prompt(remoteID, "hello")); XCTAssertTrue(core.sends.isEmpty)
        core.down = true
        roster = client.snapshot()
        XCTAssertTrue((roster["agents"] as! [Row]).allSatisfy { $0["online"] as? Bool == false })
        XCTAssertFalse((roster["discoveryError"] as! String).isEmpty)
    }

    // 8. Automatic mode uses the core when it answers, else the herdr CLI; reads and sends follow the id's backend.
    func testAutoFallbackAndRouting() throws {
        let core = Core(); core.terminals = [terminal()]
        var tuiCalls = 0
        let tui = HerdrClient(binary: "/test/herdr", execute: { call in
            tuiCalls += 1
            if call.arguments.contains("machine") { return "[]" }
            let group = call.arguments[2]
            return encode(["result": [["agent": "agents", "workspace": "workspaces", "tab": "tabs"][group]!: group == "agent" ? [["pane_id": "w1:p1", "terminal_id": "x", "workspace_id": "w1", "tab_id": "w1:t1", "agent": "codex", "agent_status": "idle", "agent_session": NSNull()]] : []]])
        })
        let defaults = UserDefaults(suiteName: "herdr-hud-test-\(UUID().uuidString)")!
        let router = BackendRouter(core: make(core), tui: tui, defaults: defaults)
        XCTAssertEqual(router.mode, .auto)
        var roster = router.snapshot()
        XCTAssertEqual(roster["backend"] as? String, "core"); XCTAssertEqual(tuiCalls, 0)
        let coreID = (roster["agents"] as! [Row])[0]["id"] as! String
        XCTAssertTrue(BackendRouter.isCore(coreID))
        _ = try router.prompt(coreID, "hello"); XCTAssertEqual(core.sends.count, 1)
        core.down = true
        roster = router.snapshot()
        XCTAssertEqual(roster["backend"] as? String, "tui"); XCTAssertGreaterThan(tuiCalls, 0)
        XCTAssertFalse(BackendRouter.isCore((roster["agents"] as! [Row])[0]["id"] as! String))
        XCTAssertThrowsError(try router.prompt(coreID, "hello"))  // the fallback dropped every core binding
        XCTAssertEqual(core.sends.count, 1)
        defaults.set("core", forKey: "backendMode")
        XCTAssertEqual(router.snapshot()["backend"] as? String, "core")
        let absent = BackendRouter(core: CoreHerdrClient(binary: nil, connect: nil), tui: tui, defaults: defaults, mode: .tui)
        XCTAssertEqual(absent.snapshot()["backend"] as? String, "tui")
    }

    func testLabelFallbacksWithoutDocument() {
        var t = terminal(); t["title"] = "✳ Fix the build"; t["status"] = ["app": "claude-code", "state": "idle"]
        let row = CoreHerdrClient.agent(t, machine: "local", label: "Mac", place: nil, home: "/Users/test")
        XCTAssertEqual(row["tab_label"] as? String, "Fix the build"); XCTAssertEqual(row["workspace_label"] as? String, "~")
        XCTAssertEqual(row["workspace_id"] as? String, "sp1"); XCTAssertEqual(row["tab_id"] as? String, "tb1"); XCTAssertEqual(row["pane_id"] as? String, "t7")
        t["title"] = ""; t["status"] = ["state": "idle"]; t["foreground"] = ["argv": ["/usr/local/bin/codex", "--x"]]; t["labels"] = [:]; t["cwd"] = "/srv/app"
        let bare = CoreHerdrClient.agent(t, machine: "local", label: "Mac", place: nil, home: "/Users/test")
        XCTAssertEqual(bare["agent"] as? String, "codex"); XCTAssertEqual(bare["tab_label"] as? String, "codex"); XCTAssertEqual(bare["workspace_label"] as? String, "app")
        XCTAssertEqual(bare["workspace_id"] as? String, "/srv/app")
    }

    // CR 1. A child that closes stderr early must not turn the wait for its reply into a busy loop.
    func testClosedStderrDoesNotSpin() throws {
        let pipe = try RPCPipe(executable: "/usr/bin/python3", arguments: ["-c", "import os,sys,json,time\nos.close(2)\nfor l in sys.stdin:\n r=json.loads(l)\n time.sleep(1)\n print(json.dumps({'id':r['id'],'result':{'ok':True}}),flush=True)"])
        defer { pipe.close() }
        func cpu() -> Double { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6 }
        let before = cpu(), start = Date()
        XCTAssertEqual((try pipe.call("x", [:], timeout: 5) as? Row)?["ok"] as? Bool, true)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.9)
        XCTAssertLessThan(cpu() - before, 0.3)
        XCTAssertFalse(pipe.errOpen)
    }

    // CR 2. Automatic mode: an empty or offline-only core must not hide an active herdr CLI; offline core cards stay when TUI is empty.
    func testAutoAsksTuiWhenCoreIsEmpty() throws {
        var tuiAgents: [Row] = [["pane_id": "w1:p1", "terminal_id": "x", "workspace_id": "w1", "tab_id": "w1:t1", "agent": "codex", "agent_status": "idle", "agent_session": NSNull()]]
        var tuiCalls = 0
        func tui(_ binary: String?) -> HerdrClient {
            HerdrClient(binary: binary, execute: { call in
                tuiCalls += 1
                if call.arguments.contains("machine") { return "[]" }
                let group = call.arguments[call.arguments.count - 2]
                return encode(["result": [["agent": "agents", "workspace": "workspaces", "tab": "tabs"][group]!: group == "agent" ? tuiAgents : []]])
            })
        }
        let defaults = UserDefaults(suiteName: "herdr-hud-test-\(UUID().uuidString)")!
        let empty = Core()
        XCTAssertEqual(BackendRouter(core: make(empty), tui: tui("/test/herdr"), defaults: defaults).snapshot()["backend"] as? String, "tui")
        tuiAgents = []
        XCTAssertEqual(BackendRouter(core: make(empty), tui: tui("/test/herdr"), defaults: defaults).snapshot()["backend"] as? String, "core")
        tuiCalls = 0
        XCTAssertEqual(BackendRouter(core: make(empty), tui: tui("/usr/bin/env"), defaults: defaults).snapshot()["backend"] as? String, "core")
        XCTAssertEqual(tuiCalls, 0)  // no herdr CLI installed: never asked
        let busy = Core(); busy.terminals = [terminal()]
        tuiAgents = [["pane_id": "w1:p1", "terminal_id": "x", "workspace_id": "w1", "agent": "codex", "agent_status": "idle"]]
        XCTAssertEqual(BackendRouter(core: make(busy), tui: tui("/test/herdr"), defaults: defaults).snapshot()["backend"] as? String, "core")
        XCTAssertEqual(tuiCalls, 0)  // a core with live agents wins without asking the CLI
        // Disconnected remote Core machine leaves cached online=false cards: live TUI wins, else Core keeps its offline cards.
        let offlineOnly = Core()
        let rohan: Row = ["name": "rohan", "id": "m1", "host": "rohan", "target": "rohan", "version": "0.1.22", "state": "connected"]
        offlineOnly.machines = [rohan]; offlineOnly.terminals = [terminal("rohan/t2")]
        let coreClient = make(offlineOnly)
        _ = coreClient.snapshot()
        offlineOnly.machines = [rohan.merging(["state": "unreachable"], uniquingKeysWith: { _, b in b })]; offlineOnly.terminals = []
        XCTAssertEqual(BackendRouter(core: coreClient, tui: tui("/test/herdr"), defaults: defaults).snapshot()["backend"] as? String, "tui")
        tuiAgents = []
        let kept = BackendRouter(core: coreClient, tui: tui("/test/herdr"), defaults: defaults).snapshot()
        XCTAssertEqual(kept["backend"] as? String, "core")
        XCTAssertEqual((kept["agents"] as? [Row])?.count, 1)
        XCTAssertEqual((kept["agents"] as? [Row])?.first?["online"] as? Bool, false)
    }

    // CR 3. The bound program ignores foreground.argv, which follows whatever runs in front of the agent.
    func testForegroundCommandNeverBreaksBinding() throws {
        for app in ["codex", nil] as [String?] {
            let core = Core()
            var t = terminal(); t["argv"] = ["/bin/zsh"]; t["foreground"] = ["argv": ["codex", "--no-daemon"]]
            t["status"] = app.map { ["app": $0, "state": "idle"] } ?? ["state": "idle"]
            core.terminals = [t]
            let client = make(core); let agent = (client.snapshot()["agents"] as! [Row])[0]
            XCTAssertEqual(agent["agent"] as? String, "codex")  // shown program: Chat view still selects codex
            t["foreground"] = ["argv": ["rg", "pattern"]]; core.terminals = [t]  // the agent runs a tool
            XCTAssertEqual((client.snapshot()["agents"] as! [Row])[0]["id"] as? String, agent["id"] as? String)
            XCTAssertEqual(try client.output(agent["id"] as! String)["id"] as? String, agent["id"] as? String)
            XCTAssertEqual(try client.prompt(agent["id"] as! String, "hello")["ok"] as? Bool, true)
            XCTAssertEqual(core.sends.count, 1)
        }
        var t = terminal(); t["status"] = ["state": "idle"]; t["argv"] = ["/opt/homebrew/bin/claude"]; t["foreground"] = NSNull()
        XCTAssertEqual(CoreHerdrClient.program(t), "claude"); XCTAssertEqual(CoreHerdrClient.shownProgram(t), "claude")
    }

    // CR 4. Switching backend drops the other backend's selection; TUI machine id "core" never collides with Core prefix.
    func testSelectionAfterBackendSwitch() {
        let core = CoreHerdrClient.identity(machine: "local", address: "t7", created: "1", provider: "codex"), tui = encode(["local", "", "default", "w1:p1", "x", NSNull()])
        let tuiMachineNamedCore = HerdrClient.key(Machine(id: "core", label: "Core Box", target: "corebox", session: "default"), ["pane_id": "w1:p1", "terminal_id": "term1", "agent_session": NSNull()])
        let legacyCore = encode(["core", "local", "t7", "1", "codex"])
        XCTAssertTrue(core.hasPrefix("core:")); XCTAssertFalse(BackendRouter.isCore(tuiMachineNamedCore))
        XCTAssertEqual(BackendRouter.migrateSelection(legacyCore), core)
        XCTAssertEqual(BackendRouter.migrateSelection(tuiMachineNamedCore), tuiMachineNamedCore)
        XCTAssertTrue(BackendRouter.selectionSurvives(core, after: .core)); XCTAssertFalse(BackendRouter.selectionSurvives(core, after: .tui))
        XCTAssertTrue(BackendRouter.selectionSurvives(legacyCore, after: .core)); XCTAssertFalse(BackendRouter.selectionSurvives(legacyCore, after: .tui))
        XCTAssertTrue(BackendRouter.selectionSurvives(tui, after: .tui)); XCTAssertFalse(BackendRouter.selectionSurvives(tui, after: .core))
        XCTAssertTrue(BackendRouter.selectionSurvives(tuiMachineNamedCore, after: .tui)); XCTAssertFalse(BackendRouter.selectionSurvives(tuiMachineNamedCore, after: .core))
        for mode in BackendRouter.Mode.allCases { XCTAssertTrue(BackendRouter.selectionSurvives("shepherdr:p:Mac:~", after: mode)); XCTAssertTrue(BackendRouter.selectionSurvives("", after: mode)) }
        XCTAssertTrue(BackendRouter.selectionSurvives(core, after: .auto)); XCTAssertTrue(BackendRouter.selectionSurvives(tui, after: .auto))
    }
}
