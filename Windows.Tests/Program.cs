using HerdrHUD;
using System.Text.Json.Nodes;

static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
static async Task Refused(Func<Task> action, string contains)
{
    try { await action(); } catch (InvalidOperationException e) { Check(e.Message.Contains(contains, StringComparison.OrdinalIgnoreCase), e.Message); return; }
    throw new Exception("Expected refusal: " + contains);
}
static List<string> ShellWords(string text)
{
    var words = new List<string>(); var word = new System.Text.StringBuilder(); char quote = '\0'; bool started = false;
    foreach(char c in text)
    {
        if (quote != '\0') { if(c==quote)quote='\0';else word.Append(c); started=true; }
        else if(c=='\'' || c=='"') { quote=c; started=true; }
        else if(char.IsWhiteSpace(c)) { if(started){words.Add(word.ToString());word.Clear();started=false;} }
        else { word.Append(c);started=true; }
    }
    Check(quote=='\0',"Unterminated shell quote");if(started)words.Add(word.ToString());return words;
}
var passed = 0;
async Task Test(string name, Func<Task> run) { await run(); passed++; Console.WriteLine("PASS " + name); }

await Test("idle prompts go once, with literal Unicode multiline argv", async () => {
    var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client);
    string prompt = "hello 'quoted' $(do-not-run) `literal`\n世界";
    await client.Prompt(id, prompt); Check(fake.Sends == 1 && fake.Last!.Arguments[^1] == prompt, "Prompt changed or duplicated");
});
await Test("busy, blocked and unknown states refuse sends", async () => {
    foreach (string state in new[] { "working", "blocked", "unknown", "" }) { var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client); fake.Status = state; await Refused(() => client.Prompt(id, "hello"), "busy"); Check(fake.Sends == 0, "Sent to busy agent"); }
});
await Test("replaced pane identity refuses output and prompts", async () => {
    var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client); fake.Terminal = "replacement";
    await Refused(() => client.Prompt(id, "hello"), "replaced"); await Refused(() => client.Output(id), "replaced"); Check(fake.Sends == 0, "Stale send");
});
await Test("conversation and workspace replacements refuse", async () => {
    foreach (bool conversation in new[] {true,false}) { var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client); if(conversation)fake.Conversation="new";else fake.Workspace="new"; await Refused(() => client.Prompt(id,"hello"),"replaced"); Check(fake.Sends == 0,"Sent to replacement"); }
});
await Test("offline cache remains visible but cannot send, reconnect recovers", async () => {
    var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client); fake.Offline = true;
    var snapshot = await client.Snapshot(); Check(snapshot["agents"]![0]!["online"]!.GetValue<bool>() == false, "Cache missing or online");
    await Refused(() => client.Prompt(id, "hello"), "offline"); fake.Offline = false; Check((await client.Snapshot())["agents"]![0]!["online"]!.GetValue<bool>(), "Did not reconnect");
});
await Test("saved machine removal or target change refuses stale sends", async () => {
    foreach (bool remove in new[]{true,false}) { var fake = new Fake{Remote=true}; var client=fake.Client(); var snapshot=await client.Snapshot(); string id=snapshot["agents"]![1]!["id"]!.GetValue<string>(); if(remove)fake.Remote=false;else fake.Target="new-host";await Refused(()=>client.Prompt(id,"hello"),"configuration changed");Check(fake.Sends==0,"Sent to changed host"); }
});
await Test("ambiguous delivery never retries", async () => {
    var fake = new Fake { BadAck = true }; var client = fake.Client(); var id = await fake.ID(client);
    await Refused(() => client.Prompt(id,"hello"), "uncertain"); Check(fake.Sends == 1, "Retried delivery");
});
await Test("validation rejects empty, dash-leading, NUL and oversized messages before transport", async () => {
    var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client);
    foreach (string message in new[]{"", "  ", "-flag", "a\0b", new string('界',20001)}) await Refused(() => client.Prompt(id,message), "under 60 KB"); Check(fake.Sends == 0, "Invalid send");
});
await Test("local, root and nested SSH preserve literal command arguments", () => {
    var client = new HerdrClient("user@source"); var machine = new Machine("remote", "Remote", "my-alias", "named session");
    string prompt = "hello ' $(touch /tmp/never) `literal`\nUnicode 世界";
    var invocation = client.Invoke(machine, ["agent","prompt","p1",prompt],true);
    Check(invocation.Mutation && invocation.Arguments[^2]=="user@source", "Wrong root target");
    var outer = ShellWords(invocation.Arguments[^1]);
    Check(outer[0] == "ssh" && outer[^2] == "my-alias", "Wrong nested target");
    var inner = ShellWords(outer[^1]);
    Check(inner[0] == "sh" && inner[1] == "-c" && inner[5] == "named session" && inner[^1] == prompt, "Nested argv changed");
    Check(invocation.Arguments.Contains("StrictHostKeyChecking=yes"), "Untrusted host allowed");
    return Task.CompletedTask;
});
await Test("invalid SSH targets rejected", async () => {
    foreach(string target in new[]{"-oProxyCommand=bad", "host name", "host\ncommand"}) {
        var client = new HerdrClient(target); await Refused(() => Task.FromResult(client.Invoke(new Machine("local","Root",null,"default"),["agent","list"])), "target");
    }
});
await Test("source and named session are part of identity", () => {
    var row = Fake.Agent("idle","t1","w1","c1"); var machine = new Machine("local","Source",null,"default");
    Check(new HerdrClient("first").Key(machine,row) != new HerdrClient("second").Key(machine,row),"Root collision");
    Check(new HerdrClient("first","one").Key(machine,row) != new HerdrClient("first","two").Key(machine,row),"Session collision"); return Task.CompletedTask;
});
await Test("process output drains stdout and stderr without deadlock", async () => {
    var runner = new ProcessRunner(); string raw = await runner.Run(new Invocation("powershell.exe", ["-NoProfile", "-Command", "[Console]::Out.Write(('x'*150000)); [Console]::Error.Write(('y'*150000))"])); Check(raw.Length == 150000,"Output truncated");
});
Console.WriteLine($"{passed} tests passed.");

sealed class Fake
{
    public string Status = "idle", Terminal = "t1", Workspace = "w1", Conversation = "c1", Target="remote-host";
    public bool Offline, BadAck, Remote;
    public int Sends;
    public Invocation? Last;
    public static JsonObject Agent(string status,string terminal,string workspace,string conversation) => new() { ["pane_id"]="p1", ["terminal_id"]=terminal,["workspace_id"]=workspace,["tab_id"]="tab1",["agent_session"]=conversation,["agent"]="codex",["agent_status"]=status };
    public HerdrClient Client() => new(binary:"herdr-test.exe", execute:Run);
    public async Task<string> ID(HerdrClient client) => (await client.Snapshot())["agents"]![0]!["id"]!.GetValue<string>();
    Task<string> Run(Invocation invocation)
    {
        Last=invocation; var args=invocation.Arguments;
        // Saved remote calls contain a quoted command; identify read operations only.
        var text=string.Join(" ",args);
        if (text.Contains("machine") && text.Contains("list")) return Task.FromResult(Remote ? new JsonArray(new JsonObject{["id"]="remote",["target"]=Target,["session"]="default",["enabled"]=true}).ToJsonString() : "[]");
        if (Offline) throw new InvalidOperationException("offline fixture");
        if(invocation.Mutation){Sends++;return Task.FromResult(BadAck?"broken ack":"{\"result\":{\"ok\":true}}");}
        if(text.Contains("workspace"))return Task.FromResult("{\"result\":{\"workspaces\":[]}}");
        if(text.Contains("tab"))return Task.FromResult("{\"result\":{\"tabs\":[]}}");
        if(text.Contains("read"))return Task.FromResult("• Fixture output");
        return Task.FromResult(new JsonObject{["result"]=new JsonObject{["agents"]=new JsonArray(Agent(Status,Terminal,Workspace,Conversation))}}.ToJsonString());
    }
}
