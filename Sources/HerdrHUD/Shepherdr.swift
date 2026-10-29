import Foundation

/// Shepherdr mode: spaces and tasks come from the local Shepherdr server's read-only snapshot (the one interface that
/// covers every machine), and each coordinator or task agent is linked to the herdr agent Shepherdr started for it by
/// the herdr agent name in Shepherdr's own agent records. Reads and sends then use HerdrClient's checked path unchanged.
/// An agent that no longer runs (a merged task) opens read only, showing its Shepherdr chat.
final class ShepherdrClient {
    struct Record: Equatable { let machine: String?, key: String, name: String }  // machine: herdr machine id, nil on the main machine
    let home: URL
    let fetch: (URLComponents) throws -> Data
    var last: Row?, chats = Set<String>()
    init(home: URL? = nil, fetch: ((URLComponents) throws -> Data)? = nil) {
        let root = home ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".shepherdr")
        self.home = root
        self.fetch = fetch ?? { try Self.download(root, $0) }
    }
    static func download(_ home: URL, _ address: URLComponents) throws -> Data {
        var port = 7787
        if let data = try? Data(contentsOf: home.appendingPathComponent("server.json")), let saved = (try? JSONSerialization.jsonObject(with: data) as? Row)?["port"] as? Int, (1...65535).contains(saved) { port = saved }
        var components = address; components.scheme = "http"; components.host = "127.0.0.1"; components.port = port
        guard let url = components.url else { throw HUDError("Invalid Shepherdr address.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        let done = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(HUDError("Shepherdr isn't answering on this Mac."))
        let task = URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            if let data = data, (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 16_777_216 { result = .success(data) }
            else if error == nil { result = .failure(HUDError("Shepherdr returned an unexpected answer.")) }
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + 6) == .success else { task.cancel(); throw HUDError("Shepherdr timed out.") }
        return try result.get()
    }
    /// Shepherdr's agent records: this machine's, then each other machine's worker folder, named by herdr's machine id.
    func records() -> [Record] {
        var found: [Record] = []
        func load(_ url: URL, _ machine: String?) {
            guard let data = try? Data(contentsOf: url), let rows = (try? JSONSerialization.jsonObject(with: data)) as? [String: Row] else { return }
            for (key, row) in rows.sorted(by: { $0.key < $1.key }) where row["finished"] as? Bool != true {
                if let name = row["name"] as? String, !name.isEmpty { found.append(Record(machine: machine, key: key, name: name)) }
            }
        }
        load(home.appendingPathComponent("agents.json"), nil)
        let folders = (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent("machines"), includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("last.json")),
                  let id = (((try? JSONSerialization.jsonObject(with: data)) as? Row)?["saved"] as? Row)?["id"] as? String, !id.isEmpty else { continue }
            load(folder.appendingPathComponent("agents.json"), id)
        }
        return found
    }
    /// The HUD id of the one herdr agent Shepherdr runs for this chat key, or nil when none or more than one matches.
    static func link(_ chat: String?, machine: String, host: String, records: [Record], agents: [Row]) -> String? {
        guard let chat = chat, !chat.isEmpty else { return nil }
        let local = machine == host
        let matches = records.filter { $0.key == chat && (local ? $0.machine == nil : $0.machine != nil) }.flatMap { record in
            agents.filter { row in
                row["name"] as? String == record.name &&
                (local ? row["machine_id"] as? String == "local" : row["machine_id"] as? String == record.machine && row["machine_label"] as? String == machine)
            }
        }
        return matches.count == 1 ? matches[0]["id"] as? String : nil
    }
    func overlay(agents: [Row]) -> Row {
        do {
            guard let snapshot = try JSONSerialization.jsonObject(with: try fetch(URLComponents(string: "/api/snapshot")!)) as? Row, let places = snapshot["places"] as? [Row], let tasks = snapshot["tasks"] as? [Row] else { throw HUDError("Shepherdr returned an unsupported format.") }
            let host = snapshot["host"] as? String ?? "", records = records()
            var names: [String: String] = [:]
            for machine in snapshot["machines"] as? [Row] ?? [] { if let key = machine["machine"] as? String { names[key] = machine["name"] as? String ?? key } }
            let asks = snapshot["asks"] as? Row ?? [:], attention = snapshot["attentionRequests"] as? Row ?? [:]
            var machineOf: [String: String] = [:]
            let spaces: [Row] = places.compactMap { place in
                guard let id = place["id"] as? String, let machine = place["machine"] as? String else { return nil }
                machineOf[id] = machine
                // Another machine's chats reach the main server only while its web app watches them: read only this Mac's.
                let chat = place["chat"] as? String ?? "", readable = machine == host ? chat : ""
                return ["id": id, "name": place["name"] as? String ?? id, "machine": names[machine] ?? machine, "home": place["home"] as? Bool ?? false, "chat": readable,
                        "status": place["status"] as? String ?? "", "need": asks[id] != nil || !((attention[chat] as? [Any]) ?? []).isEmpty,
                        "offline": place["unreachableSince"] != nil || place["herdrDown"] != nil,
                        "agent_id": Self.link(chat, machine: machine, host: host, records: records, agents: agents) ?? NSNull()]
            }
            let rows: [Row] = tasks.compactMap { task in
                // Shepherdr keeps when a task was archived (ms); an archived task is out of every list.
                guard let id = task["id"] as? String, let place = task["place"] as? String, let machine = machineOf[place], ((task["archived"] as? NSNumber)?.doubleValue ?? 0) == 0 else { return nil }
                let status = task["status"] as? String ?? "", chat = (task["agent"] as? Row)?["chat"] as? String ?? ""
                return ["id": id, "title": task["name"] as? String ?? id, "status": status, "sub": task["sub"] as? String ?? "", "place": place, "need": status == "need", "chat": machine == host ? chat : "",
                        "agent_id": Self.link(chat, machine: machine, host: host, records: records, agents: agents) ?? NSNull()]
            }
            let result: Row = ["spaces": spaces, "tasks": rows, "error": ""]
            last = result
            chats = Set((spaces + rows).compactMap { $0["chat"] as? String }.filter { !$0.isEmpty })
            return result
        } catch {
            return (last ?? ["spaces": [Row](), "tasks": [Row]()]).merging(["error": error.localizedDescription], uniquingKeysWith: { _, b in b })
        }
    }
    /// The latest messages of a chat from the last roster, as plain text: only a key the roster showed is read.
    func transcript(_ chat: String) throws -> Row {
        guard chats.contains(chat) else { throw HUDError("This Shepherdr chat is no longer listed. Refresh and select it again.") }
        var address = URLComponents(string: "/api/chat")!; address.queryItems = [URLQueryItem(name: "chat", value: chat)]
        guard let object = try JSONSerialization.jsonObject(with: try fetch(address)) as? Row, let messages = (object["chat"] as? Row)?["messages"] as? [Row] else { throw HUDError("Shepherdr has no chat for this agent.") }
        let lines = messages.compactMap { message -> String? in
            guard let text = message["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (message["who"] as? String == "you" ? "You" : "Agent") + "\n" + text
        }.suffix(40)
        return ["id": "shepherdr:" + chat, "provider": "shepherdr", "text": String(lines.joined(separator: "\n\n").suffix(60_000))]
    }
}
