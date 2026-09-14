using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;

namespace HerdrHUD;

public record Invocation(string Executable, string[] Arguments, bool Mutation = false, byte[]? Input = null, bool LocalPrompt = false);
public record Machine(string Id, string Label, string? Target, string Session);

public static class Json
{
    public static string Text(this JsonObject row, string key) => row[key]?.GetValueKind() == System.Text.Json.JsonValueKind.String ? row[key]!.GetValue<string>() : "";
    public static bool Flag(this JsonObject row, string key) => row[key]?.GetValueKind() == System.Text.Json.JsonValueKind.True;
    public static JsonObject Copy(this JsonObject row) => (JsonObject)row.DeepClone();
}

// Calls are serialized by the host. No terminal is prompted without fresh identity,
// configuration, and readiness checks. A submitted prompt is never retried.
public sealed class HerdrClient
{
    readonly Func<Invocation, Task<string>> execute;
    readonly string binary, sourceTarget, sourceSession;
    readonly Dictionary<string, List<JsonObject>> cache = new();
    Dictionary<string, (Machine Machine, JsonObject Agent)> bindings = new();
    List<Machine> machines = [];
    const string Script = "unset HERDR_ENV HERDR_SOCKET_PATH HERDR_CONFIG_PATH HERDR_SESSION HERDR_SESSION_NAME HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_PANE_ID HERDR_TERMINAL_ID; if [ -x \"$HOME/.local/bin/herdr\" ]; then exec \"$HOME/.local/bin/herdr\" \"$@\"; elif [ -x /opt/homebrew/bin/herdr ]; then exec /opt/homebrew/bin/herdr \"$@\"; else exec herdr \"$@\"; fi";
    public HerdrClient(string sourceTarget = "", string sourceSession = "default", string? binary = null, Func<Invocation, Task<string>>? execute = null)
    {
        this.sourceTarget = sourceTarget.Trim(); this.sourceSession = sourceSession;
        this.binary = binary ?? FindBinary(); this.execute = execute ?? new ProcessRunner().Run;
    }
    static string FindBinary()
    {
        string candidate = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Herdr", "bin", "herdr.exe");
        return File.Exists(candidate) ? candidate : "herdr.exe";
    }
    public static string Quote(string text) => "'" + text.Replace("'", "'\"'\"'") + "'";
    public static void ValidateTarget(string target)
    {
        if (string.IsNullOrWhiteSpace(target) || target.StartsWith('-') || target.Any(c => char.IsWhiteSpace(c) || char.IsControl(c))) throw new InvalidOperationException("Invalid saved SSH target.");
    }
    static string Command(IEnumerable<string> args) => string.Join(" ", args.Select(Quote));
    static string[] SshArgs(string target, string command) => ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=yes", target, command];
    public Invocation Invoke(Machine machine, string[] args, bool mutation = false, byte[]? input = null)
    {
        string[] scoped = ["--session", machine.Session, ..args];
        if (scoped.Any(s => s.Contains('\0'))) throw new InvalidOperationException("Invalid command argument.");
        var posix = mutation ? Command(["python3","-c",File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Resources","prompt.py"))]) : Command(["sh", "-c", Script, "herdr-hud", ..scoped]);
        if (machine.Target is not null) ValidateTarget(machine.Target);
        var ssh = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "OpenSSH", "ssh.exe");
        if (sourceTarget.Length > 0)
        {
            ValidateTarget(sourceTarget);
            // The source host resolves its own saved SSH aliases and credentials.
            var remote = machine.Target is null ? posix : Command(["ssh", ..SshArgs(machine.Target, posix)]);
            return new Invocation(ssh, SshArgs(sourceTarget, remote), mutation,input);
        }
        return machine.Target is null ? new Invocation(binary, scoped, mutation,input,mutation) : new Invocation(ssh, SshArgs(machine.Target, posix), mutation,input);
    }
    Task<string> Call(Machine machine, string[] args, bool mutation = false) => execute(Invoke(machine, args, mutation));
    async Task<List<JsonObject>> Rows(Machine machine, string kind)
    {
        var raw = await Call(machine, [kind, "list"]);
        var node = JsonNode.Parse(raw)?["result"]?[kind switch { "agent" => "agents", "workspace" => "workspaces", "tab" => "tabs", _ => throw new InvalidOperationException() }] as JsonArray;
        if (node is null || node.Any(n => n is not JsonObject)) throw new InvalidOperationException("Herdr returned an unsupported roster format.");
        return node.OfType<JsonObject>().ToList();
    }
    Machine Root => new("local", sourceTarget.Length == 0 ? Environment.MachineName : "Herdr source", null, sourceSession);
    async Task<List<Machine>> Discover()
    {
        var saved = JsonNode.Parse(await Call(Root, ["machine", "list", "--json"])) as JsonArray ?? throw new InvalidOperationException("Cannot read Herdr's saved machines.");
        var found = new List<Machine> { Root }; var seen = new HashSet<string> { "local" };
        foreach (var row in saved.OfType<JsonObject>().Where(r => r.Flag("enabled")))
        {
            var id = row.Text("id"); var target = row.Text("target");
            if (id.Length == 0 || target.Length == 0 || !seen.Add(id)) continue;
            found.Add(new Machine(id, row.Text("label") is { Length: > 0 } label ? label : target, target, row.Text("session") is { Length: > 0 } session ? session : "default"));
        }
        return found;
    }
    public string Key(Machine machine, JsonObject row) => new JsonArray(sourceTarget, sourceSession, machine.Id, machine.Target ?? "", machine.Session, row.Text("pane_id"), row.Text("terminal_id"), row["agent_session"]?.DeepClone()).ToJsonString();
    public async Task<JsonObject> Snapshot()
    {
        string error = "";
        try { machines = await Discover(); } catch (Exception e) { error = e.Message; if (machines.Count == 0) machines = [Root]; }
        var all = new JsonArray(); var states = new JsonArray(); var next = new Dictionary<string, (Machine, JsonObject)>();
        foreach (var machine in machines)
        {
            var state = new JsonObject { ["id"] = machine.Id, ["label"] = machine.Label, ["session"] = machine.Session };
            try
            {
                var agents = await Rows(machine, "agent"); var spaces = await Rows(machine, "workspace"); var tabs = await Rows(machine, "tab");
                var enriched = new List<JsonObject>();
                foreach (var agent in agents)
                {
                    string key = Key(machine, agent); var row = agent.Copy();
                    row["id"] = key; row["machine_label"] = machine.Label; row["machine_id"] = machine.Id; row["online"] = true;
                    row["workspace_label"] = spaces.FirstOrDefault(s => s.Text("workspace_id") == agent.Text("workspace_id"))?.Text("label") ?? agent.Text("workspace_id");
                    row["tab_label"] = tabs.FirstOrDefault(s => s.Text("tab_id") == agent.Text("tab_id"))?.Text("label") ?? agent.Text("tab_id");
                    enriched.Add(row); next[key] = (machine, agent);
                }
                cache[machine.Id] = enriched; foreach (var row in enriched) all.Add(row.Copy());
                state["online"] = true; state["count"] = enriched.Count;
            }
            catch (Exception e)
            {
                foreach (var cached in cache.GetValueOrDefault(machine.Id) ?? []) { var row = cached.Copy(); row["online"] = false; all.Add(row); }
                state["online"] = false; state["error"] = e.Message;
            }
            states.Add(state);
        }
        bindings = next;
        foreach (var id in cache.Keys.Where(id => !machines.Any(m => m.Id == id)).ToArray()) cache.Remove(id);
        return new JsonObject { ["agents"] = all, ["machines"] = states, ["discoveryError"] = error };
    }
    async Task<(Machine Machine, JsonObject Agent)> Resolve(string id)
    {
        if (!bindings.TryGetValue(id, out var binding)) throw new InvalidOperationException("Agent is offline or changed. Refresh and select it again.");
        if (!(await Discover()).Contains(binding.Machine)) throw new InvalidOperationException("This machine's Herdr configuration changed. Refresh before sending.");
        var current = (await Rows(binding.Machine, "agent")).FirstOrDefault(r => r.Text("pane_id") == binding.Agent.Text("pane_id"));
        if (current is null || Key(binding.Machine, current) != id || current.Text("workspace_id") != binding.Agent.Text("workspace_id") || current.Text("agent") != binding.Agent.Text("agent")) throw new InvalidOperationException("The selected agent was replaced. Select its new session.");
        return (binding.Machine, current);
    }
    public async Task<JsonObject> Output(string id)
    {
        var (machine, agent) = await Resolve(id);
        return new JsonObject { ["id"] = id, ["provider"] = agent.Text("agent"), ["text"] = await Call(machine, ["agent", "read", agent.Text("pane_id"), "--source", "recent-unwrapped", "--lines", "180"]) };
    }
    public async Task<JsonObject> Prompt(string id, string message)
    {
        if (string.IsNullOrWhiteSpace(message) || Encoding.UTF8.GetByteCount(message) > 60000 || message.Contains('\0') || message.StartsWith('-')) throw new InvalidOperationException("Enter a prompt under 60 KB that does not start with a dash.");
        var (machine, agent) = await Resolve(id);
        if (agent.Text("agent_status") is not ("idle" or "done")) throw new InvalidOperationException("This agent is busy or needs input. Answer native questions in Herdr.");
        var input=Encoding.UTF8.GetBytes(new JsonObject{["session"]=machine.Session,["agent"]=agent.DeepClone(),["text"]=message}.ToJsonString()+"\n");
        string raw;
        try { raw = await execute(Invoke(machine, ["status","server"],true,input)); }
        catch { throw new InvalidOperationException("Delivery uncertain or refused. Inspect Herdr before sending again."); }
        JsonObject? response = null; try { response = JsonNode.Parse(raw) as JsonObject; } catch (System.Text.Json.JsonException) { }
        if (response?["result"]?["type"]?.GetValue<string>() != "agent_prompted" || response?["result"]?["agent"]?["terminal_id"]?.GetValue<string>() != agent.Text("terminal_id") || response?["error"] is not null) throw new InvalidOperationException("Delivery uncertain. Inspect Herdr before sending again.");
        return new JsonObject { ["ok"] = true, ["id"] = id };
    }
}
