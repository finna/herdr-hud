import XCTest
@testable import HerdrHUD
final class ShepherdrTests: XCTestCase {
    func agent(_ name: String, id: String, machine: String = "local", label: String = "This Mac", status: String = "idle") -> Row {
        ["id":id,"name":name,"machine_id":machine,"machine_label":label,"agent_status":status,"online":true]
    }
    func snapshot(tasks: [Row]? = nil) -> Data {
        let places: [Row] = [["id":"p:Mac:~","name":"home","machine":"Mac","home":true,"status":"need","chat":"p:Mac:~"],
                             ["id":"p:Mac:app","name":"app","machine":"Mac","status":"work","chat":"p:Mac:app"],
                             ["id":"p:Laptop:~","name":"home","machine":"Laptop","home":true,"status":"off","chat":"p:Laptop:~","unreachableSince":"16:00"]]
        let tasks = tasks ?? [["id":"APP-1","name":"First","status":"need","sub":"Waits for your reply","place":"p:Mac:app","agent":["chat":"APP-1/Agent"]],
                              ["id":"APP-2","name":"Second","status":"done","sub":"Merged","place":"p:Mac:app","agent":["chat":"APP-2/Agent"]],
                              ["id":"APP-3","name":"Archived","status":"done","place":"p:Mac:app","archived":1793300000000,"agent":["chat":"APP-3/Agent"]],
                              ["id":"LAP-1","name":"Remote","status":"work","place":"p:Laptop:~","agent":["chat":"LAP-1/Agent"]]]
        return Data(encode(["host":"Mac","places":places,"tasks":tasks,"machines":[["machine":"Mac","name":"Mac Studio"],["machine":"Laptop","name":"Laptop"]],
                            "asks":["p:Mac:app":["x"]],"attentionRequests":[:],"settings":[["name":"Private","value":"never copied"]]]).utf8)
    }
    func home(records: [String: Row], remote: [String: Row] = [:], remoteID: String = "m-laptop") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shepherdr-test-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("machines/Laptop")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encode(records).write(to: root.appendingPathComponent("agents.json"), atomically: true, encoding: .utf8)
        try encode(["saved":["id":remoteID,"label":"Laptop"]]).write(to: folder.appendingPathComponent("last.json"), atomically: true, encoding: .utf8)
        try encode(remote).write(to: folder.appendingPathComponent("agents.json"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    let records: [String: Row] = ["p:Mac:~":["name":"shepherdr-home"],"p:Mac:app":["name":"shep-app"],"APP-1/Agent":["name":"shep-app-1"],"APP-2/Agent":["name":"shep-app-2","finished":true]]
    func testSpacesAndTasksLinkToTheirHerdrAgents() throws {
        let client = ShepherdrClient(home: try home(records: records, remote: ["LAP-1/Agent":["name":"shep-lap-1"]]), fetch: { _ in self.snapshot() })
        let agents = [agent("shepherdr-home", id:"H"), agent("shep-app", id:"C"), agent("shep-app-1", id:"T1"), agent("shep-app-2", id:"T2"), agent("shep-lap-1", id:"R", machine:"m-laptop", label:"Laptop"), agent("unrelated", id:"U")]
        let result = client.overlay(agents: agents)
        XCTAssertEqual(result["error"] as? String, "")
        let spaces = result["spaces"] as! [Row], tasks = result["tasks"] as! [Row]
        XCTAssertEqual(spaces.map { $0["agent_id"] as? String }, ["H","C",nil])
        XCTAssertEqual(spaces.map { $0["machine"] as? String }, ["Mac Studio","Mac Studio","Laptop"])
        XCTAssertEqual(spaces.map { $0["need"] as? Bool }, [false,true,false], "a coordinator needs you only when it asks, not from its tasks")
        XCTAssertEqual(spaces[2]["offline"] as? Bool, true)
        XCTAssertEqual(tasks.map { $0["id"] as? String }, ["APP-1","APP-2","LAP-1"], "archived tasks stay out")
        XCTAssertEqual(tasks.map { $0["agent_id"] as? String }, ["T1",nil,"R"], "a finished record links nothing")
        XCTAssertEqual(tasks[0]["need"] as? Bool, true)
        XCTAssertNil(result["settings"], "only spaces and tasks leave the Shepherdr snapshot")
        XCTAssertEqual(spaces.map { $0["chat"] as? String }, ["p:Mac:~","p:Mac:app",""]); XCTAssertEqual(tasks.map { $0["chat"] as? String }, ["APP-1/Agent","APP-2/Agent",""])
    }
    func testNotRunningAgentReadsOnlyAListedShepherdrChat() throws {
        var asked: [String] = []
        let client = ShepherdrClient(home: try home(records: records), fetch: { address in
            asked.append(address.string ?? "")
            if address.path == "/api/chat" { return Data(encode(["chat":["messages":[["who":"you","text":"Ship it"],["who":"agent","text":""],["who":"agent","text":"Merged."]]]]).utf8) }
            return self.snapshot()
        })
        XCTAssertThrowsError(try client.transcript("APP-2/Agent"), "nothing is read before the roster lists it")
        _ = client.overlay(agents: [])
        let result = try client.transcript("APP-2/Agent")
        XCTAssertEqual(result["text"] as? String, "You\nShip it\n\nAgent\nMerged.")
        XCTAssertEqual(result["id"] as? String, "shepherdr:APP-2/Agent")
        XCTAssertEqual(asked.last, "/api/chat?chat=APP-2/Agent")
        XCTAssertThrowsError(try client.transcript("SECRET/Agent")); XCTAssertThrowsError(try client.transcript("APP-3/Agent"), "an archived task's chat is not listed")
        XCTAssertThrowsError(try client.transcript("LAP-1/Agent"), "another machine's chat is only cached on the main server")
        XCTAssertEqual(asked.count, 2)
    }
    func testLinkRefusesWrongMachineAndAmbiguousNames() {
        let records = [ShepherdrClient.Record(machine: nil, key: "A/Agent", name: "shep-a"), ShepherdrClient.Record(machine: "m1", key: "B/Agent", name: "shep-b")]
        XCTAssertNil(ShepherdrClient.link("A/Agent", machine: "Mac", host: "Mac", records: records, agents: [agent("shep-a", id:"X", machine:"m1", label:"Mac")]), "a local record never links a remote agent")
        XCTAssertNil(ShepherdrClient.link("A/Agent", machine: "Mac", host: "Mac", records: records, agents: [agent("shep-a", id:"X"), agent("shep-a", id:"Y")]), "two matches link nothing")
        XCTAssertNil(ShepherdrClient.link("B/Agent", machine: "Laptop", host: "Mac", records: records, agents: [agent("shep-b", id:"X", machine:"m1", label:"Other")]), "the herdr machine must carry the space's machine name")
        XCTAssertEqual(ShepherdrClient.link("B/Agent", machine: "Laptop", host: "Mac", records: records, agents: [agent("shep-b", id:"X", machine:"m1", label:"Laptop")]), "X")
        XCTAssertNil(ShepherdrClient.link("C/Agent", machine: "Mac", host: "Mac", records: records, agents: [agent("shep-c", id:"X")]), "no record: no guess from names")
    }
    func testUnreachableShepherdrKeepsLastRosterWithError() throws {
        var up = true
        let client = ShepherdrClient(home: try home(records: records), fetch: { _ in if up { return self.snapshot() }; throw HUDError("Shepherdr isn't answering on this Mac.") })
        _ = client.overlay(agents: [])
        up = false
        let result = client.overlay(agents: [])
        XCTAssertEqual((result["spaces"] as? [Row])?.count, 3)
        XCTAssertEqual(result["error"] as? String, "Shepherdr isn't answering on this Mac.")
        XCTAssertEqual(ShepherdrClient(home: try home(records: records), fetch: { _ in Data("[]".utf8) }).overlay(agents: [])["error"] as? String, "Shepherdr returned an unsupported format.")
    }
    func testLinkedTaskSendsOnlyThroughCheckedHerdrPath() throws {
        var state = "working", sent: [Invocation] = []
        let herdr = HerdrClient(binary:"/test/herdr", execute:{ call in
            if call.mutation { sent.append(call); return "{\"result\":{\"type\":\"agent_prompted\",\"agent\":{\"terminal_id\":\"term1\"}}}" }
            if call.arguments.contains("machine") { return "[]" }
            let group = call.arguments[2]
            let row: Row = ["pane_id":"w1:p2","terminal_id":"term1","workspace_id":"w1","tab_id":"w1:t1","agent":"claude","name":"shep-app-1","agent_status":state]
            return encode(["result":[["agent":"agents","workspace":"workspaces","tab":"tabs"][group]!: group == "agent" ? [row] : []]])
        })
        let roster = herdr.snapshot()
        let overlay = ShepherdrClient(home: try home(records: records), fetch: { _ in self.snapshot() }).overlay(agents: roster["agents"] as! [Row])
        let id = try XCTUnwrap((overlay["tasks"] as! [Row])[0]["agent_id"] as? String)
        XCTAssertThrowsError(try herdr.prompt(id, "follow-up")); XCTAssertTrue(sent.isEmpty, "a working task agent is refused")
        state = "done"
        _ = try herdr.prompt(id, "follow-up"); XCTAssertEqual(sent.count, 1)
    }
}
