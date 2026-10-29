import Foundation

/// Shepherdr mode: spaces and tasks come from the local Shepherdr server's read-only snapshot (the one interface that
/// covers every machine), and each coordinator or task agent is linked to the herdr agent Shepherdr started for it by
/// the herdr agent name in Shepherdr's own agent records. Reads and sends then use HerdrClient's checked path unchanged.
final class ShepherdrClient {
    struct Record: Equatable { let machine: String?, key: String, name: String }  // machine: herdr machine id, nil on the main machine
    let home: URL
    let fetch: () throws -> Data
    var last: Row?
    init(home: URL? = nil, fetch: (() throws -> Data)? = nil) {
        let root = home ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".shepherdr")
        self.home = root
        self.fetch = fetch ?? { try Self.download(root) }
    }
    static func download(_ home: URL) throws -> Data {
        var port = 7787
        if let data = try? Data(contentsOf: home.appendingPathComponent("server.json")), let saved = (try? JSONSerialization.jsonObject(with: data) as? Row)?["port"] as? Int, (1...65535).contains(saved) { port = saved }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/snapshot")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        let done = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(HUDError("Shepherdr isn't answering on this Mac."))
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            if let data = data, (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 16_777_216 { result = .success(data) }
            else if error == nil { result = .failure(HUDError("Shepherdr returned an unexpected answer.")) }
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + 6) == .success else { throw HUDError("Shepherdr timed out.") }
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
            guard let snapshot = try JSONSerialization.jsonObject(with: try fetch()) as? Row, let places = snapshot["places"] as? [Row], let tasks = snapshot["tasks"] as? [Row] else { throw HUDError("Shepherdr returned an unsupported format.") }
            let host = snapshot["host"] as? String ?? "", records = records()
            var names: [String: String] = [:]
            for machine in snapshot["machines"] as? [Row] ?? [] { if let key = machine["machine"] as? String { names[key] = machine["name"] as? String ?? key } }
            let asks = snapshot["asks"] as? Row ?? [:], attention = snapshot["attentionRequests"] as? Row ?? [:]
            var machineOf: [String: String] = [:]
            let spaces: [Row] = places.compactMap { place in
                guard let id = place["id"] as? String, let machine = place["machine"] as? String else { return nil }
                machineOf[id] = machine
                let chat = place["chat"] as? String ?? ""
                return ["id": id, "name": place["name"] as? String ?? id, "machine": names[machine] ?? machine, "home": place["home"] as? Bool ?? false,
                        "status": place["status"] as? String ?? "", "need": asks[id] != nil || !((attention[chat] as? [Any]) ?? []).isEmpty,
                        "offline": place["unreachableSince"] != nil || place["herdrDown"] != nil,
                        "agent_id": Self.link(chat, machine: machine, host: host, records: records, agents: agents) ?? NSNull()]
            }
            let rows: [Row] = tasks.compactMap { task in
                guard let id = task["id"] as? String, let place = task["place"] as? String, let machine = machineOf[place], task["archived"] as? Bool != true else { return nil }
                let status = task["status"] as? String ?? ""
                return ["id": id, "title": task["name"] as? String ?? id, "status": status, "sub": task["sub"] as? String ?? "", "place": place, "need": status == "need",
                        "agent_id": Self.link((task["agent"] as? Row)?["chat"] as? String, machine: machine, host: host, records: records, agents: agents) ?? NSNull()]
            }
            let result: Row = ["spaces": spaces, "tasks": rows, "error": ""]
            last = result
            return result
        } catch {
            return (last ?? ["spaces": [Row](), "tasks": [Row]()]).merging(["error": error.localizedDescription], uniquingKeysWith: { _, b in b })
        }
    }
}
