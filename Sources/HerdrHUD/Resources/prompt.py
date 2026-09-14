"""Fixed remote helper. Request arrives only on stdin; no prompt is in argv.
Requires Python 3 on a remote Mac/Linux Herdr host. No files are installed.
"""
import json, os, selectors, signal, socket, subprocess, sys, time
LIMIT = 1024 * 1024
DEADLINE = time.monotonic() + 12

def remaining():
    value = DEADLINE - time.monotonic()
    if value <= 0: raise RuntimeError('Request timed out')
    return value

def status(binary, session):
    env = {k:v for k,v in os.environ.items() if not k.startswith('HERDR_')}
    p = subprocess.Popen([binary, '--session', session, 'status', 'server'], stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, start_new_session=True)
    data = [bytearray(), bytearray()]
    try:
        with selectors.DefaultSelector() as sel:
            for i,f in enumerate([p.stdout,p.stderr]):
                os.set_blocking(f.fileno(), False);sel.register(f, selectors.EVENT_READ,i)
            while sel.get_map() or p.poll() is None:
                for key,_ in sel.select(min(remaining(),.05)):
                    i=key.data;chunk=os.read(key.fd,min(4096,65537-len(data[i])))
                    if not chunk: sel.unregister(key.fileobj)
                    elif len(data[i])+len(chunk)>65536: raise RuntimeError('Status output limit exceeded')
                    else: data[i].extend(chunk)
        if p.returncode: raise RuntimeError('Herdr status unavailable')
        return next(line[8:].strip() for line in data[0].decode().splitlines() if line.startswith('socket: '))
    finally:
        try: os.killpg(p.pid,signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait();p.stdout.close();p.stderr.close()

def rpc(path, method, params):
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(remaining());s.connect(path)
        s.sendall((json.dumps({'id':'hud','method':method,'params':params})+'\n').encode())
        data=bytearray()
        while b'\n' not in data:
            s.settimeout(remaining());chunk=s.recv(min(16384,LIMIT+1-len(data)))
            if not chunk: raise RuntimeError('Missing acknowledgement')
            data.extend(chunk)
            if len(data)>LIMIT: raise RuntimeError('Socket output limit exceeded')
    value=json.loads(data.split(b'\n',1)[0])
    if value.get('id')!='hud' or 'error' in value or not isinstance(value.get('result'),dict):
        raise RuntimeError('Herdr rejected the request or returned an invalid acknowledgement')
    return value['result']

def main():
    data=bytearray()
    with selectors.DefaultSelector() as sel:
        sel.register(sys.stdin,selectors.EVENT_READ)
        while b'\n' not in data:
            if not sel.select(remaining()): raise RuntimeError('Input timed out')
            chunk=os.read(sys.stdin.fileno(),min(4096,524289-len(data)))
            if not chunk: raise RuntimeError('Missing input')
            data.extend(chunk)
            if len(data)>524288: raise RuntimeError('Input limit exceeded')
    request=json.loads(data.split(b'\n',1)[0]);expected=request['agent'];text=request['text']
    if not isinstance(text,str) or not text.strip() or len(text.encode())>60000 or '\0' in text: raise RuntimeError('Invalid prompt')
    binary=next((p for p in [os.path.expanduser('~/.local/bin/herdr'),'/opt/homebrew/bin/herdr','/usr/local/bin/herdr'] if os.access(p,os.X_OK)),'herdr')
    path=status(binary,request['session'])
    current=rpc(path,'agent.get',{'target':expected['pane_id']}).get('agent',{})
    for key in ['pane_id','terminal_id','workspace_id','agent','agent_session']:
        if current.get(key)!=expected.get(key): raise RuntimeError('Agent changed')
    if current.get('agent_status') not in ['idle','done']: raise RuntimeError('Agent is not ready')
    result=rpc(path,'agent.prompt',{'target':expected['pane_id'],'text':text})
    if result.get('type')!='agent_prompted' or result.get('agent',{}).get('terminal_id')!=expected['terminal_id']: raise RuntimeError('Invalid prompt acknowledgement')
    print(json.dumps({'result':result}))

if __name__=='__main__':
    try: main()
    except Exception:
        print('Delivery refused or uncertain. Inspect Herdr before sending again.',file=sys.stderr)
        sys.exit(1)
