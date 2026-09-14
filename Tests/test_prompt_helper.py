import json, os, pathlib, socket, subprocess, sys, tempfile, threading, unittest
HELPER=pathlib.Path(__file__).resolve().parents[1]/'Sources/HerdrHUD/Resources/prompt.py'
class PromptHelperTests(unittest.TestCase):
    def scenario(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);path=str(root/'socket');binary=root/'.local/bin/herdr';binary.parent.mkdir(parents=True)
            binary.write_text('#!'+sys.executable+'\nprint('+repr('socket: '+path)+')\n');binary.chmod(0o700)
            listener=socket.socket(socket.AF_UNIX);listener.bind(path);listener.listen();listener.settimeout(3)
            expected={'pane_id':'w1:p1','terminal_id':'terminal','workspace_id':'w1','agent':'codex','agent_session':{'value':'test'}}
            received=[];failures=[]
            def serve():
                try:
                    for _ in range(1 if mode in ['replaced','blocked'] else 2):
                        con,_=listener.accept()
                        with con:
                            request=json.loads(con.makefile('rb').readline());received.append(request)
                            agent={**expected,'agent_status':'idle'}
                            if mode=='replaced':agent['terminal_id']='new'
                            if mode=='blocked':agent['agent_status']='blocked'
                            if request['method']=='agent.prompt':
                                if mode=='disconnect':continue
                                if mode=='overflow':
                                    try:con.sendall(b'x'*1048577)
                                    except BrokenPipeError:pass
                                    continue
                            result={'type':'agent_info' if request['method']=='agent.get' else 'agent_prompted','agent':agent}
                            con.sendall((json.dumps({'id':request['id'],'result':result})+'\n').encode())
                except Exception as error:failures.append(error)
            thread=threading.Thread(target=serve);thread.start()
            message="secret 🐑\n$(nothing) 'quote'"
            result=subprocess.run([sys.executable,str(HELPER)],input=json.dumps({'session':'default','agent':expected,'text':message})+'\n',text=True,capture_output=True,env={**os.environ,'HOME':directory},timeout=5)
            thread.join(4);listener.close();self.assertFalse(thread.is_alive());self.assertFalse(failures,str(failures))
            if mode=='success':
                self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(received[1]['params']['text'],message)
                self.assertEqual(json.loads(result.stdout)['result']['type'],'agent_prompted')
            else:self.assertNotEqual(result.returncode,0)
            self.assertEqual(len(received),1 if mode in ['replaced','blocked'] else 2)
    def test_success(self):self.scenario('success')
    def test_replaced(self):self.scenario('replaced')
    def test_blocked(self):self.scenario('blocked')
    def test_disconnect_no_retry(self):self.scenario('disconnect')
    def test_socket_overflow(self):self.scenario('overflow')
if __name__=='__main__':unittest.main()
