import Foundation
import Darwin

final class ProcessRunner {
    static let stdoutLimit = 1_048_576, stderrLimit = 65_536
    let timeout: TimeInterval
    init(timeout: TimeInterval = 12) { self.timeout = timeout }
    func run(_ invocation: Invocation) throws -> String {
        if invocation.localPrompt {
            let status = try run(Invocation(executable: invocation.executable, arguments: invocation.arguments, mutation: false))
            guard let path = status.components(separatedBy:"\n").first(where:{$0.hasPrefix("socket: ")}).map({String($0.dropFirst(8))}), let input = invocation.input else { throw HUDError("Cannot locate Herdr socket.") }
            return try LocalPrompt.send(path:path,input:input,timeout:timeout)
        }
        guard (invocation.input?.count ?? 0) <= 524288 else { throw HUDError("Input limit exceeded.") }
        let input = Pipe(), output = Pipe(), error = Pipe()
        let handles = [input.fileHandleForReading,input.fileHandleForWriting,output.fileHandleForReading,output.fileHandleForWriting,error.fileHandleForReading,error.fileHandleForWriting]
        defer { for h in handles { try? h.close() } }
        for h in handles { _ = fcntl(h.fileDescriptor,F_SETFD,FD_CLOEXEC) }
        var actions: posix_spawn_file_actions_t?, attr: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions);posix_spawnattr_init(&attr)
        defer {posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attr)}
        posix_spawn_file_actions_adddup2(&actions,input.fileHandleForReading.fileDescriptor,0)
        posix_spawn_file_actions_adddup2(&actions,output.fileHandleForWriting.fileDescriptor,1)
        posix_spawn_file_actions_adddup2(&actions,error.fileHandleForWriting.fileDescriptor,2)
        posix_spawnattr_setflags(&attr,Int16(POSIX_SPAWN_SETPGROUP));posix_spawnattr_setpgroup(&attr,0)
        var env=ProcessInfo.processInfo.environment.filter{!$0.key.hasPrefix("HERDR_")}
        env["PATH"]=NSHomeDirectory()+"/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let av=([invocation.executable]+invocation.arguments).map{strdup($0)}+[nil]
        let ev=env.map{strdup("\($0.key)=\($0.value)")}+[nil]
        defer {for p in av+ev {if let p=p {free(p)}}}
        var pid:pid_t=0
        let code=av.withUnsafeBufferPointer{a in ev.withUnsafeBufferPointer{e in posix_spawn(&pid,invocation.executable,&actions,&attr,UnsafeMutablePointer(mutating:a.baseAddress!),UnsafeMutablePointer(mutating:e.baseAddress!))}}
        guard code==0 else {throw HUDError("Could not launch Herdr or SSH (\(code)).")}
        try? input.fileHandleForReading.close();try? output.fileHandleForWriting.close();try? error.fileHandleForWriting.close()
        var reaped=false,status:Int32=0
        defer {
            _=kill(-pid,SIGKILL)
            if !reaped {while waitpid(pid,&status,0)<0 && errno==EINTR {}}
        }
        signal(SIGPIPE,SIG_IGN)
        let inFD=input.fileHandleForWriting.fileDescriptor,outFD=output.fileHandleForReading.fileDescriptor,errFD=error.fileHandleForReading.fileDescriptor
        for fd in [inFD,outFD,errFD] {_=fcntl(fd,F_SETFL,O_NONBLOCK)}
        var pending=invocation.input ?? Data(), out=Data(), err=Data()
        var inputOpen=true,outOpen=true,errOpen=true
        let deadline=Date().addingTimeInterval(timeout)
        while !reaped || outOpen || errOpen {
            if Date()>=deadline {throw HUDError(invocation.mutation ? "Delivery uncertain. Inspect Herdr before sending again." : "Machine timed out.")}
            if inputOpen && pending.isEmpty {try? input.fileHandleForWriting.close();inputOpen=false}
            var fds=[pollfd(fd:outOpen ? outFD : -1,events:Int16(POLLIN),revents:0),pollfd(fd:errOpen ? errFD : -1,events:Int16(POLLIN),revents:0),pollfd(fd:inputOpen ? inFD : -1,events:Int16(POLLOUT),revents:0)]
            _=poll(&fds,3,20)
            if inputOpen && fds[2].revents != 0 {
                let count=pending.withUnsafeBytes{Darwin.write(inFD,$0.baseAddress!,min(4096,pending.count))}
                if count>0 {pending.removeFirst(count)} else if errno != EAGAIN && errno != EINTR {throw HUDError("Delivery uncertain. Prompt pipe closed.")}
            }
            for i in 0...1 where fds[i].revents != 0 {
                let limit=i==0 ? Self.stdoutLimit : Self.stderrLimit
                let used=i==0 ? out.count : err.count
                var chunk=[UInt8](repeating:0,count:min(16384,limit-used+1))
                let count=Darwin.read(i==0 ? outFD : errFD,&chunk,chunk.count)
                if count==0 {if i==0 {outOpen=false}else{errOpen=false}}
                else if count>0 {
                    guard used+count<=limit else {throw HUDError(invocation.mutation ? "Delivery uncertain. Output limit exceeded." : "Herdr output limit exceeded.")}
                    if i==0 {out.append(contentsOf:chunk.prefix(count))}else{err.append(contentsOf:chunk.prefix(count))}
                } else if errno != EAGAIN && errno != EINTR {throw HUDError("Could not read command output.")}
            }
            if !reaped {reaped=waitpid(pid,&status,WNOHANG)==pid}
        }
        guard status==0 else {throw HUDError(invocation.mutation ? "Delivery uncertain or refused. Inspect Herdr before sending again." : String(decoding:err.prefix(700),as:UTF8.self))}
        return String(decoding:out,as:UTF8.self)
    }
}

enum LocalPrompt {
    static func rpc(path:String,method:String,params:Row,deadline:Date) throws -> Row {
        let fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else {throw HUDError("Cannot open Herdr socket.")}
        defer {_=Darwin.close(fd)}
        var noPipe:Int32=1;_=setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,socklen_t(MemoryLayout<Int32>.size))
        _=fcntl(fd,F_SETFL,O_NONBLOCK)
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
        let bytes=Array(path.utf8)+[0]
        guard bytes.count<=MemoryLayout.size(ofValue:address.sun_path) else {throw HUDError("Socket path too long.")}
        withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:bytes)}
        let connected=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard connected==0 || errno==EINPROGRESS else {throw HUDError("Cannot connect to Herdr.")}
        func ready(_ events:Int16) throws {
            while true {
                let ms=deadline.timeIntervalSinceNow*1000
                guard ms>0 else {throw HUDError("Delivery uncertain. Socket timed out.")}
                var p=pollfd(fd:fd,events:events,revents:0)
                let result=poll(&p,1,Int32(min(ms,1000)))
                if result>0 {return};if result<0 && errno != EINTR {throw HUDError("Socket failed.")}
            }
        }
        try ready(Int16(POLLOUT))
        var error:Int32=0,length=socklen_t(MemoryLayout<Int32>.size)
        _=getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&length)
        guard error==0 else {throw HUDError("Cannot connect to Herdr.")}
        let id=UUID().uuidString
        var wire=Data((encode(["id":id,"method":method,"params":params])+"\n").utf8)
        while !wire.isEmpty {
            try ready(Int16(POLLOUT));let n=wire.withUnsafeBytes{Darwin.write(fd,$0.baseAddress!,wire.count)}
            if n>0 {wire.removeFirst(n)}else if errno != EAGAIN && errno != EINTR {throw HUDError("Delivery uncertain. Socket write failed.")}
        }
        var data=Data()
        while !data.contains(10) {
            try ready(Int16(POLLIN));var chunk=[UInt8](repeating:0,count:min(16384,ProcessRunner.stdoutLimit-data.count+1))
            let n=Darwin.read(fd,&chunk,chunk.count)
            if n==0 {throw HUDError("Delivery uncertain. Missing acknowledgement.")}
            if n<0 {if errno==EAGAIN || errno==EINTR {continue};throw HUDError("Socket read failed.")}
            guard data.count+n<=ProcessRunner.stdoutLimit else {throw HUDError("Socket output limit exceeded.")}
            data.append(contentsOf:chunk.prefix(n))
        }
        guard let result=try JSONSerialization.jsonObject(with:Data(data.prefix(while:{$0 != 10}))) as? Row,result["id"] as? String==id,result["error"]==nil,let value=result["result"] as? Row else {throw HUDError("Delivery refused or uncertain. Inspect Herdr.")}
        return value
    }
    static func send(path:String,input:Data,timeout:TimeInterval) throws -> String {
        let request=try JSONSerialization.jsonObject(with:input) as! Row,expected=request["agent"] as! Row
        let deadline=Date().addingTimeInterval(timeout),pane=expected["pane_id"] as! String
        let current=try rpc(path:path,method:"agent.get",params:["target":pane],deadline:deadline)["agent"] as? Row ?? [:]
        for key in ["pane_id","terminal_id","workspace_id","agent","agent_session"] {guard encode(current[key] ?? NSNull())==encode(expected[key] ?? NSNull()) else {throw HUDError("Agent changed; no prompt sent.")}}
        guard ["idle","done"].contains(current["agent_status"] as? String ?? "") else {throw HUDError("Agent is not ready.")}
        let result=try rpc(path:path,method:"agent.prompt",params:["target":pane,"text":request["text"]!],deadline:deadline)
        guard result["type"] as? String=="agent_prompted",(result["agent"] as? Row)?["terminal_id"] as? String==expected["terminal_id"] as? String else {throw HUDError("Delivery uncertain. Invalid acknowledgement.")}
        return encode(["result":result])
    }
}
