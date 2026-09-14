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

await Test("idle prompts go once, with literal Unicode multiline stdin", async () => {
    var fake = new Fake(); var client = fake.Client(); var id = await fake.ID(client);
    string prompt = "hello 'quoted' $(do-not-run) `literal`\n世界";
    await client.Prompt(id, prompt); Check(fake.Sends == 1 && !string.Join(" ",fake.Last!.Arguments).Contains(prompt) && JsonNode.Parse(fake.Last.Input!)!["text"]!.GetValue<string>() == prompt, "Prompt changed or duplicated");
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
    var input=System.Text.Encoding.UTF8.GetBytes(new JsonObject{["text"]=prompt}.ToJsonString());
    var invocation = client.Invoke(machine, ["status","server"],true,input);
    Check(invocation.Mutation && invocation.Arguments[^2]=="user@source", "Wrong root target");
    var outer = ShellWords(invocation.Arguments[^1]);
    Check(outer[0] == "ssh" && outer[^2] == "my-alias", "Wrong nested target");
    var inner = ShellWords(outer[^1]);
    Check(inner[0] == "python3" && inner[1] == "-c" && !string.Join(" ",invocation.Arguments).Contains(prompt) && invocation.Input==input, "Nested argv changed");
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
    var runner = new ProcessRunner(); string raw = await runner.Run(new Invocation("powershell.exe", ["-NoProfile", "-Command", "[Console]::Out.Write(('x'*150000)); [Console]::Error.Write(('y'*60000))"])); Check(raw.Length == 150000,"Output truncated");
});
await Test("stdout and stderr overflow are bounded", async () => {
    foreach(string stream in new[]{"Out","Error"})await Refused(()=>new ProcessRunner(3).Run(new Invocation("powershell.exe",["-NoProfile","-Command",$"[Console]::{stream}.Write(('x'*1100000))"])),"limit");
});
await Test("stalled child group is terminated by the job", async () => {
    string file=Path.GetTempFileName();
    try {
        string script="$p=Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','Start-Sleep 20' -PassThru -NoNewWindow; [IO.File]::WriteAllText('"+file.Replace("'","''")+"',$p.Id); Start-Sleep 20";
        await Refused(()=>new ProcessRunner(2).Run(new Invocation("powershell.exe",["-NoProfile","-Command",script])),"timed out");
        int pid=int.Parse(File.ReadAllText(file));bool alive=false;try{using var child=System.Diagnostics.Process.GetProcessById(pid);alive=!child.HasExited;}catch(ArgumentException){}Check(!alive,"Child survived job cleanup");
    } finally {File.Delete(file);}
});
await Test("stdin Unicode roundtrip without command arguments", async () => {
    string text="private 🐑\n'quote' $(never)";
    var raw=await new ProcessRunner().Run(new Invocation("powershell.exe",["-NoProfile","-Command","[Console]::InputEncoding=[Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);[Console]::Out.Write([Console]::In.ReadToEnd())"],Input:System.Text.Encoding.UTF8.GetBytes(text)));
    Check(raw==text,"stdin changed");
});
await Test("local named-pipe prompt roundtrip", async () => {
    string name="herdr-hud-test-"+Guid.NewGuid();
    using var cancel=new CancellationTokenSource(TimeSpan.FromSeconds(5));
    async Task Serve(){
        foreach(string method in new[]{"agent.get","agent.prompt"}){
            using var server=new System.IO.Pipes.NamedPipeServerStream(name,System.IO.Pipes.PipeDirection.InOut,1,System.IO.Pipes.PipeTransmissionMode.Byte,System.IO.Pipes.PipeOptions.Asynchronous);
            await server.WaitForConnectionAsync(cancel.Token);
            using var reader=new StreamReader(server,System.Text.Encoding.UTF8,false,1024,true);
            var request=JsonNode.Parse((await reader.ReadLineAsync(cancel.Token))!)!;Check(request["method"]!.GetValue<string>()==method,"Wrong socket method");
            if(method=="agent.prompt")Check(request["params"]!["text"]!.GetValue<string>()=="private 🐑","Prompt altered");
            var result=new JsonObject{["id"]=request["id"]!.DeepClone(),["result"]=new JsonObject{["type"]=method=="agent.get"?"agent_info":"agent_prompted",["agent"]=Fake.Agent("idle","t1","w1","c1")}};
            await server.WriteAsync(System.Text.Encoding.UTF8.GetBytes(result.ToJsonString()+"\n"),cancel.Token);
            // Wait until the client closes this connection before accepting the next.
            Check(await server.ReadAsync(new byte[1],cancel.Token)==0,"Expected client EOF");
        }
    }
    var serving=Serve();var data=System.Text.Encoding.UTF8.GetBytes(new JsonObject{["agent"]=Fake.Agent("idle","t1","w1","c1"),["text"]="private 🐑"}.ToJsonString());
    string response=await LocalPrompt.Send(@"\\.\pipe\"+name,data,TimeSpan.FromSeconds(4));await serving;Check(response.Contains("agent_prompted"),"No acknowledgement");
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
        if(invocation.Mutation){Sends++;return Task.FromResult(BadAck?"broken ack":"{\"result\":{\"type\":\"agent_prompted\",\"agent\":{\"terminal_id\":\"t1\"}}}");}
        if(text.Contains("workspace"))return Task.FromResult("{\"result\":{\"workspaces\":[]}}");
        if(text.Contains("tab"))return Task.FromResult("{\"result\":{\"tabs\":[]}}");
        if(text.Contains("read"))return Task.FromResult("• Fixture output");
        return Task.FromResult(new JsonObject{["result"]=new JsonObject{["agents"]=new JsonArray(Agent(Status,Terminal,Workspace,Conversation))}}.ToJsonString());
    }
}
