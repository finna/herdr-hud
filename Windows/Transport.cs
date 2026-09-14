using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;
using System.Text.Json.Nodes;
using System.IO.Pipes;

namespace HerdrHUD;

// Spawn suspended, assign a kill-on-close job, then resume. Children cannot escape
// cleanup by exiting their parent before Process.Kill(entireProcessTree) runs.
sealed class OwnedProcess : IDisposable
{
    [StructLayout(LayoutKind.Sequential)] struct Startup { public int Size; public nint Reserved,Desktop,Title; public int X,Y,XSize,YSize,XCount,YCount,Fill,Flags; public short Show,Reserved2; public nint ReservedPtr,Input,Output,Error; }
    [StructLayout(LayoutKind.Sequential)] struct StartupEx { public Startup Info; public nint Attributes; }
    [StructLayout(LayoutKind.Sequential)] struct ProcInfo { public nint Process,Thread; public int Pid,Tid; }
    [StructLayout(LayoutKind.Sequential)] struct Security { public int Length; public nint Descriptor; public int Inherit; }
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits { public long ProcessTime,JobTime; public uint Flags; public nuint Min,Max; public uint Active; public nuint Affinity; public uint Priority,Scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] struct Limits { public BasicLimits Basic; public IoCounters Io; public nuint ProcessMemory,JobMemory,PeakProcess,PeakJob; }
    [DllImport("kernel32",SetLastError=true)] static extern bool CreatePipe(out nint read,out nint write,ref Security security,int size);
    [DllImport("kernel32",SetLastError=true)] static extern bool SetHandleInformation(nint handle,uint mask,uint flags);
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)] static extern nint CreateJobObject(nint attrs,string? name);
    [DllImport("kernel32",SetLastError=true)] static extern bool SetInformationJobObject(nint job,int type,ref Limits limits,int length);
    [DllImport("kernel32",SetLastError=true)] static extern bool AssignProcessToJobObject(nint job,nint process);
    [DllImport("kernel32")] static extern bool TerminateJobObject(nint job,uint code);
    [DllImport("kernel32")] static extern bool TerminateProcess(nint process,uint code);
    [DllImport("kernel32")] static extern uint ResumeThread(nint thread);
    [DllImport("kernel32")] static extern bool CloseHandle(nint handle);
    [DllImport("kernel32",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(nint list,int count,int flags,ref nuint size);
    [DllImport("kernel32",SetLastError=true)] static extern bool UpdateProcThreadAttribute(nint list,uint flags,nuint attribute,nint value,nuint size,nint previous,nint returned);
    [DllImport("kernel32")] static extern void DeleteProcThreadAttributeList(nint list);
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string? application,StringBuilder command,nint processAttrs,nint threadAttrs,bool inherit,uint flags,nint environment,string? directory,ref StartupEx startup,out ProcInfo info);
    readonly nint job;
    public Process Process {get;}
    public FileStream Input {get;}
    public FileStream Output {get;}
    public FileStream Error {get;}
    static void Require(bool ok) {if(!ok) throw new InvalidOperationException("Cannot create isolated command ("+Marshal.GetLastWin32Error()+").");}
    public static string Quote(string value) {
        var s=new StringBuilder("\"");int slashes=0;
        foreach(char c in value) {if(c=='\\'){slashes++;continue;}s.Append('\\',c=='"'?slashes*2+1:slashes);s.Append(c);slashes=0;}
        return s.Append('\\',slashes*2).Append('"').ToString();
    }
    public OwnedProcess(Invocation invocation) {
        var handles=new List<nint>();nint attrs=0,values=0,environment=0;ProcInfo info=default;bool spawned=false,success=false,initialized=false;
        job=CreateJobObject(0,null);Require(job!=0);
        try {
            var limits=new Limits();limits.Basic.Flags=0x2000;Require(SetInformationJobObject(job,9,ref limits,Marshal.SizeOf<Limits>()));
            var security=new Security{Length=Marshal.SizeOf<Security>(),Inherit=1};
            Require(CreatePipe(out var ir,out var iw,ref security,0));handles.AddRange([ir,iw]);
            Require(CreatePipe(out var or,out var ow,ref security,0));handles.AddRange([or,ow]);
            Require(CreatePipe(out var er,out var ew,ref security,0));handles.AddRange([er,ew]);
            foreach(var h in new[]{iw,or,er})Require(SetHandleInformation(h,1,0));
            nuint size=0;InitializeProcThreadAttributeList(0,1,0,ref size);attrs=Marshal.AllocHGlobal((int)size);Require(InitializeProcThreadAttributeList(attrs,1,0,ref size));initialized=true;
            values=Marshal.AllocHGlobal(3*nint.Size);Marshal.Copy(new nint[]{ir,ow,ew},0,values,3);
            Require(UpdateProcThreadAttribute(attrs,0,0x20002,values,(nuint)(3*nint.Size),0,0));
            var startup=new StartupEx{Info=new Startup{Size=Marshal.SizeOf<StartupEx>(),Flags=0x100,Input=ir,Output=ow,Error=ew},Attributes=attrs};
            var env=Environment.GetEnvironmentVariables().Cast<System.Collections.DictionaryEntry>().Where(e=>!((string)e.Key).StartsWith("HERDR_",StringComparison.Ordinal)).OrderBy(e=>(string)e.Key,StringComparer.OrdinalIgnoreCase).Select(e=>$"{e.Key}={e.Value}");
            environment=Marshal.StringToHGlobalUni(string.Join('\0',env)+"\0\0");
            var cmd=new StringBuilder(string.Join(" ",new[]{invocation.Executable}.Concat(invocation.Arguments).Select(Quote)));
            Require(CreateProcess(null,cmd,0,0,true,0x08000000|0x00080000|0x00000400|0x00000004,environment,null,ref startup,out info));spawned=true;
            Require(AssignProcessToJobObject(job,info.Process));
            Process=Process.GetProcessById(info.Pid);
            Input=new FileStream(new SafeFileHandle(iw,true),FileAccess.Write);handles.Remove(iw);
            Output=new FileStream(new SafeFileHandle(or,true),FileAccess.Read);handles.Remove(or);
            Error=new FileStream(new SafeFileHandle(er,true),FileAccess.Read);handles.Remove(er);
            Require(ResumeThread(info.Thread)!=uint.MaxValue);success=true;
        } finally {
            if(!success){if(spawned)TerminateProcess(info.Process,1);TerminateJobObject(job,1);CloseHandle(job);}
            if(info.Thread!=0)CloseHandle(info.Thread);if(info.Process!=0)CloseHandle(info.Process);
            foreach(var h in handles)CloseHandle(h);
            if(initialized)DeleteProcThreadAttributeList(attrs);if(attrs!=0)Marshal.FreeHGlobal(attrs);if(values!=0)Marshal.FreeHGlobal(values);if(environment!=0)Marshal.FreeHGlobal(environment);
        }
    }
    public void Stop(){TerminateJobObject(job,1);try{Process.WaitForExit(2000);}catch(InvalidOperationException){}}
    public void Dispose(){Stop();Input.Dispose();Output.Dispose();Error.Dispose();Process.Dispose();CloseHandle(job);}
}

public sealed class ProcessRunner
{
    public const int StdoutLimit=1048576, StderrLimit=65536;
    readonly TimeSpan timeout;
    public ProcessRunner(double seconds=15){timeout=TimeSpan.FromSeconds(seconds);}
    public async Task<string> Run(Invocation invocation) {
        if(invocation.LocalPrompt){string status=await Run(invocation with {Input=null,LocalPrompt=false,Mutation=false});var path=status.Split('\n').FirstOrDefault(s=>s.StartsWith("socket: "))?[8..].Trim() ?? throw new InvalidOperationException("Cannot locate Herdr socket.");return await LocalPrompt.Send(path,invocation.Input!,timeout);}
        if((invocation.Input?.Length??0)>524288)throw new InvalidOperationException("Input limit exceeded.");
        using var child=new OwnedProcess(invocation);
        using var cancel=new CancellationTokenSource(timeout);
        async Task<byte[]> Read(Stream stream,int limit){try{using var data=new MemoryStream();var buffer=new byte[16384];while(true){int n=await stream.ReadAsync(buffer.AsMemory(0,Math.Min(buffer.Length,limit-(int)data.Length+1)),cancel.Token);if(n==0)return data.ToArray();if(data.Length+n>limit)throw new InvalidOperationException("Herdr output limit exceeded.");data.Write(buffer,0,n);}}catch{cancel.Cancel();throw;}}
        async Task Write(){try{if(invocation.Input is not null)await child.Input.WriteAsync(invocation.Input,cancel.Token);child.Input.Close();}catch{cancel.Cancel();throw;}}
        var output=Read(child.Output,StdoutLimit);var errors=Read(child.Error,StderrLimit);var input=Write();
        var all=Task.WhenAll(output,errors,input,child.Process.WaitForExitAsync(cancel.Token));
        try {await all.WaitAsync(cancel.Token);if(child.Process.ExitCode!=0)throw new InvalidOperationException("Herdr command failed.");return Encoding.UTF8.GetString(await output);}
        catch {child.Stop();try{await all.WaitAsync(TimeSpan.FromSeconds(2));}catch{}throw new InvalidOperationException(invocation.Mutation?"Delivery uncertain or refused. Inspect Herdr before sending again.":"Herdr command timed out, failed, or exceeded its output limit.");}
    }
}

static class LocalPrompt {
    public static async Task<string> Send(string path,byte[] input,TimeSpan timeout){
        using var cancel=new CancellationTokenSource(timeout);
        var request=JsonNode.Parse(input)!.AsObject();var expected=request["agent"]!.AsObject();string pane=expected.Text("pane_id");
        async Task<JsonObject> Rpc(string method,JsonObject parameters){
            const string prefix="\\\\.\\pipe\\";
            if(!path.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Unsupported local Herdr pipe path.");
            using var pipe=new NamedPipeClientStream(".",path[prefix.Length..],PipeDirection.InOut,PipeOptions.Asynchronous);
            await pipe.ConnectAsync(cancel.Token);string id=Guid.NewGuid().ToString();
            await pipe.WriteAsync(Encoding.UTF8.GetBytes(new JsonObject{["id"]=id,["method"]=method,["params"]=parameters}.ToJsonString()+"\n"),cancel.Token);
            using var data=new MemoryStream();var chunk=new byte[16384];
            while(true){int n=await pipe.ReadAsync(chunk.AsMemory(0,Math.Min(chunk.Length,ProcessRunner.StdoutLimit-(int)data.Length+1)),cancel.Token);if(n==0)throw new InvalidOperationException("Missing acknowledgement.");if(data.Length+n>ProcessRunner.StdoutLimit)throw new InvalidOperationException("Socket output limit exceeded.");int end=Array.IndexOf(chunk,(byte)10,0,n);data.Write(chunk,0,end<0?n:end);if(end>=0)break;}
            var value=JsonNode.Parse(data.ToArray())!.AsObject();if(value.Text("id")!=id||value["error"] is not null||value["result"] is not JsonObject result)throw new InvalidOperationException("Delivery refused or uncertain.");return result;
        }
        var current=(await Rpc("agent.get",new(){["target"]=pane}))["agent"]!.AsObject();
        foreach(var key in new[]{"pane_id","terminal_id","workspace_id","agent","agent_session"})if(!JsonNode.DeepEquals(current[key],expected[key]))throw new InvalidOperationException("Agent changed; no prompt sent.");
        if(current.Text("agent_status") is not("idle" or "done"))throw new InvalidOperationException("Agent is not ready.");
        var result=await Rpc("agent.prompt",new(){["target"]=pane,["text"]=request["text"]!.DeepClone()});
        if(result.Text("type")!="agent_prompted" || result["agent"]?["terminal_id"]?.GetValue<string>()!=expected.Text("terminal_id"))throw new InvalidOperationException("Invalid acknowledgement.");
        return new JsonObject{["result"]=result.DeepClone()}.ToJsonString();
    }
}
