import XCTest
import Darwin
@testable import HerdrHUD
final class TransportTests: XCTestCase {
    let machine = Machine(id:"local",label:"Test",target:nil,session:"default")
    func row(_ state:String = "idle",terminal:String = "term1",session:String = "chat1") -> Row {
        ["pane_id":"w1:p1","terminal_id":terminal,"workspace_id":"w1","tab_id":"w1:t1","agent":"codex","agent_status":state,"agent_session":["value":session]]
    }
    func testLiteralRemoteArguments() throws {
        let client = HerdrClient(binary:"/test/herdr")
        let remote = Machine(id:"r",label:"Remote",target:"remote",session:"dev")
        let prompt = "hello 'world'; $(touch /tmp/not-executed)\nsecond line `whoami`"
        let input=Data((encode(["text":prompt])+"\n").utf8)
        let inv = try client.invocation(remote,["status","server"],mutation:true,input:input)
        XCTAssertEqual(inv.executable,"/usr/bin/ssh"); XCTAssertTrue(inv.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertFalse(inv.arguments.joined().contains(prompt))
        XCTAssertEqual(inv.input,input)
    }
    func testMalformedTargetRefused() throws {
        let client = HerdrClient()
        for target in ["-oProxyCommand=evil","bad host", "bad\nname"] {
            XCTAssertThrowsError(try client.invocation(Machine(id:"r",label:"r",target:target,session:"default"),["agent","list"]))
        }
    }
    func testIdentityIncludesHostTerminalAndConversation() {
        let original = HerdrClient.key(machine,row())
        XCTAssertNotEqual(original,HerdrClient.key(machine,row(terminal:"replacement")))
        XCTAssertNotEqual(original,HerdrClient.key(machine,row(session:"replacement")))
        XCTAssertNotEqual(original,HerdrClient.key(Machine(id:"remote",label:"Remote",target:"remote",session:"default"),row()))
    }
    func clientWith(_ state: @escaping () -> Row, sends: @escaping (Invocation) throws -> String = { _ in "{\"result\":{\"type\":\"agent_prompted\",\"agent\":{\"terminal_id\":\"term1\"}}}" }) -> HerdrClient {
        HerdrClient(binary:"/test/herdr",execute:{ call in
            if call.mutation { return try sends(call) }
            if call.arguments.contains("machine") { return "[]" }
            if call.arguments.contains("read") { return "• Actual reply" }
            let group = call.arguments[2]
            return encode(["result":[["agent":"agents","workspace":"workspaces","tab":"tabs"][group]!: group == "agent" ? [state()] : []]])
        })
    }
    func testReadyPromptOnceAndLiteral() throws {
        var sent:[Invocation]=[];let client = clientWith({self.row()},sends:{ sent.append($0); return "{\"result\":{\"type\":\"agent_prompted\",\"agent\":{\"terminal_id\":\"term1\"}}}" })
        let snapshot=client.snapshot();let id=(snapshot["agents"] as! [Row])[0]["id"] as! String
        _ = try client.prompt(id,"literal $(printf secret)\nsecond line")
        XCTAssertEqual(sent.count,1);XCTAssertFalse(sent[0].arguments.joined().contains("printf secret"));XCTAssertTrue(String(decoding:sent[0].input!,as:UTF8.self).contains("printf secret"));XCTAssertTrue(sent[0].localPrompt)
    }
    func testBusyBlockedUnknownNeverSend() throws {
        for status in ["working","blocked","unknown"] {var sent=false;let client=clientWith({self.row(status)},sends:{_ in sent=true;return "{}"});let id=(client.snapshot()["agents"] as! [Row])[0]["id"] as! String;XCTAssertThrowsError(try client.prompt(id,"hello"));XCTAssertFalse(sent)}
    }
    func testReplacementRefusedForReadAndPrompt() throws {
        var current=row();var sent=false;let client=clientWith({current},sends:{_ in sent=true;return "{}"});let id=(client.snapshot()["agents"] as! [Row])[0]["id"] as! String
        current=row(session:"replacement");XCTAssertThrowsError(try client.output(id));XCTAssertThrowsError(try client.prompt(id,"hello"));XCTAssertFalse(sent)
    }
    func testUnknownOutcomeNeverRetries() throws {
        var sends=0;let client=clientWith({self.row()},sends:{_ in sends+=1;throw HUDError("Delivery uncertain")});let id=(client.snapshot()["agents"] as! [Row])[0]["id"] as! String
        XCTAssertThrowsError(try client.prompt(id,"hello"));XCTAssertEqual(sends,1)
    }
    func testMalformedAcknowledgementUncertain() throws {
        let client=clientWith({self.row()},sends:{_ in "not-json"});let id=(client.snapshot()["agents"] as! [Row])[0]["id"] as! String
        XCTAssertThrowsError(try client.prompt(id,"hello")){XCTAssertTrue($0.localizedDescription.contains("uncertain"))}
    }
    func testRejectsOptionLikeEmptyAndNulPrompts() {
        let client=clientWith({self.row()});let id=(client.snapshot()["agents"] as! [Row])[0]["id"] as! String
        for text in ["", "  ", "--help", "x\0y"] {XCTAssertThrowsError(try client.prompt(id,text))}
    }
    func testLargeOutputDoesNotDeadlock() throws {
        let runner=ProcessRunner();let output=try runner.run(Invocation(executable:"/usr/bin/awk",arguments:["BEGIN { for (i=0;i<20000;i++) print \"abcdefghij\" }"],mutation:false));XCTAssertGreaterThan(output.count,200000)
    }
}
extension TransportTests {
    func testDiscoverUsesSavedEnabledMachinesAndSessions() throws {
        let client=HerdrClient(binary:"/test/herdr",execute:{_ in encode([["id":"remote","label":"Build Mac","target":"host","session":"named","enabled":true],["id":"disabled","target":"disabled","enabled":false]])})
        let found=try client.discover();XCTAssertEqual(found.count,2);XCTAssertEqual(found[1].session,"named");XCTAssertEqual(found[1].target,"host")
    }
    func testMachineRemovedBetweenSnapshotAndSendRefused() throws {
        var saved=true,sent=false
        let client=HerdrClient(binary:"/test/herdr",execute:{ call in
            if call.mutation {sent=true;return "{\"result\":{}}"}
            if call.arguments.contains("machine"){return saved ? encode([["id":"remote","label":"Remote","target":"host","session":"default","enabled":true]]) : "[]"}
            let remote=call.executable=="/usr/bin/ssh"
            let group=remote ? ["agent","workspace","tab"].first{call.arguments.last!.contains(shellQuote($0))}! : call.arguments[2]
            return encode(["result":[["agent":"agents","workspace":"workspaces","tab":"tabs"][group]!:group=="agent" ? [self.row()] : []]])
        })
        let agents=client.snapshot()["agents"] as! [Row];let id=agents.first{$0["machine_id"] as? String == "remote"}!["id"] as! String;saved=false
        XCTAssertThrowsError(try client.prompt(id,"hello"));XCTAssertFalse(sent)
    }
    func testOfflineCachedRosterCannotSendAndLocalSurvives() throws {
        var offline=false,sent=false
        let client=HerdrClient(binary:"/test/herdr",execute:{call in
            if call.mutation {sent=true;return "{\"result\":{}}"}
            if call.arguments.contains("machine"){return encode([["id":"remote","label":"Remote","target":"host","session":"default","enabled":true]])}
            let remote=call.executable=="/usr/bin/ssh"
            if remote && offline {throw HUDError("offline")}
            let group=remote ? ["agent","workspace","tab"].first{call.arguments.last!.contains(shellQuote($0))}! : call.arguments[2]
            return encode(["result":[["agent":"agents","workspace":"workspaces","tab":"tabs"][group]!:group=="agent" ? [self.row()] : []]])
        })
        _=client.snapshot();offline=true
        let agents=client.snapshot()["agents"] as! [Row];XCTAssertEqual(agents.count,2)
        let remote=agents.first{$0["machine_id"] as? String == "remote"}!,local=agents.first{$0["machine_id"] as? String == "local"}!
        XCTAssertEqual(local["online"] as? Bool,true);XCTAssertEqual(remote["online"] as? Bool,false)
        XCTAssertThrowsError(try client.prompt(remote["id"] as! String,"hello"));XCTAssertFalse(sent)
        offline=false;XCTAssertTrue((client.snapshot()["agents"] as! [Row]).allSatisfy{$0["online"] as? Bool == true})
    }
}

extension TransportTests {
    func testOutputLimitsAndTimeout() throws {
        for fd in ["", " > \"/dev/stderr\""] {
            XCTAssertThrowsError(try ProcessRunner().run(Invocation(executable:"/usr/bin/awk",arguments:["BEGIN { for(i=0;i<110000;i++) print \"abcdefghij\""+fd+" }"],mutation:false)))
        }
        let start=Date()
        XCTAssertThrowsError(try ProcessRunner(timeout:0.2).run(Invocation(executable:"/bin/sh",arguments:["-c","sleep 10 & wait"],mutation:false)))
        XCTAssertLessThan(Date().timeIntervalSince(start),2)
    }
    func testStdinLiteralAndNotInArguments() throws {
        let text="private 'text' 🐑\n$(nothing)"
        let inv=Invocation(executable:"/bin/cat",arguments:[],mutation:false,input:Data(text.utf8))
        XCTAssertEqual(try ProcessRunner().run(inv),text)
    }
    func testChildIsKilledAfterParentExits() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:file)}
        let script="sleep 20 & echo $! > "+shellQuote(file.path)+"; exit 0"
        XCTAssertThrowsError(try ProcessRunner(timeout:0.3).run(Invocation(executable:"/bin/sh",arguments:["-c",script],mutation:false)))
        let pid=Int32(try String(contentsOf:file,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines))!
        for _ in 0..<30 {if kill(pid,0) != 0 {return};Thread.sleep(forTimeInterval:0.05)}
        XCTFail("Child survived command cleanup")
    }
}

extension TransportTests {
    func testLocalSocketPromptRoundtrip() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let path=folder.appendingPathComponent("api.sock").path
        let script="""
        import socket,json,sys
        s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.listen()
        for method in ['agent.get','agent.prompt']:
            c,_=s.accept()
            with c:
                r=json.loads(c.makefile('rb').readline());assert r['method']==method
                if method=='agent.prompt': assert r['params']['text']=="private 🐑"
                a={'pane_id':'w1:p1','terminal_id':'term1','workspace_id':'w1','agent':'codex','agent_session':{'value':'chat1'},'agent_status':'idle'}
                c.sendall((json.dumps({'id':r['id'],'result':{'type':'agent_info' if method=='agent.get' else 'agent_prompted','agent':a}})+'\\n').encode())
        """
        let server=Process();server.executableURL=URL(fileURLWithPath:"/usr/bin/python3");server.arguments=["-c",script,path];try server.run()
        defer {if server.isRunning {server.terminate()};server.waitUntilExit()}
        for _ in 0..<100 {if FileManager.default.fileExists(atPath:path){break};Thread.sleep(forTimeInterval:0.02)}
        let input=Data(encode(["agent":row(),"text":"private 🐑"]).utf8)
        let result=try LocalPrompt.send(path:path,input:input,timeout:2)
        XCTAssertTrue(result.contains("agent_prompted"))
    }
}
