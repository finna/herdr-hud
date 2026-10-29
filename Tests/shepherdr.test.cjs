const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {shepherdrRows}=require('../Sources/HerdrHUD/Resources/model.js');
const agent=(id,status,extra={})=>({id,terminal_id:id,agent_status:status,online:true,agent:'claude',machine_label:'Mac Studio',workspace_label:'w',...extra});
const data={spaces:[{id:'p:Mac:app',name:'app',machine:'Mac Studio',agent_id:'C',need:false},{id:'p:Lap:~',name:'home',machine:'Laptop',agent_id:null,offline:true}],
  tasks:[{id:'APP-2',title:'Merged one',status:'done',sub:'Merged',place:'p:Mac:app',agent_id:null,chat:'APP-2/Agent'},{id:'APP-3',title:'Busy',status:'work',sub:'Writing tests',place:'p:Mac:app',agent_id:'B'},
    {id:'APP-1',title:'Asks',status:'need',sub:'Waits for your reply',place:'p:Mac:app',agent_id:'N'},{id:'APP-9',title:'Elsewhere',status:'work',place:'p:Gone:x',agent_id:'B'}]};
const agents=[agent('C','idle'),agent('B','working'),agent('N','done')];
test('spaces lead their tasks, needs-you first and merged last',()=>{
  const rows=shepherdrRows(data,agents);
  assert.deepEqual(rows.map(r=>r.key),['space:p:Mac:app','task:APP-1','task:APP-3','task:APP-2','space:p:Lap:~']);
  assert.deepEqual(rows.map(r=>r.state),['Idle','Needs you','Working','Merged','Offline']);
  assert.equal(rows[1].title,'APP-1 · Asks');assert.equal(rows[1].need,true);assert.equal(rows[3].agent_id,'');assert.equal(rows[4].agent_id,'');
  assert.equal(rows[3].view_id,'shepherdr:APP-2/Agent','a merged task opens its Shepherdr chat');assert.equal(rows[4].view_id,'','no agent and no chat: nothing to open');
});
test('a row links only an agent the herdr roster has',()=>{assert.equal(shepherdrRows(data,[agent('C','idle')]).find(r=>r.key==='task:APP-3').agent_id,'');assert.deepEqual(shepherdrRows(null,agents),[]);});

const source=fs.readFileSync(path.join(__dirname,'../Sources/HerdrHUD/Resources/app.js'),'utf8'),model=fs.readFileSync(path.join(__dirname,'../Sources/HerdrHUD/Resources/model.js'),'utf8');
class Node{constructor(tag){this.tag=tag;this.children=[];this.attrs={};this.textContent='';this.value='';this.style={};this.hidden=false;this.disabled=false;}
  append(...n){this.children.push(...n);}replaceChildren(...n){this.children=n;}setAttribute(k,v){this.attrs[k]=v;}getAttribute(k){return this.attrs[k];}
  querySelectorAll(){return [];}querySelector(){return null;}dispatchEvent(e){this['on'+e.type]?.(e);}click(){this.onclick?.();}}
function harness(platform){
  const nodes=new Map(),messages=[];
  const document={getElementById(id){if(!nodes.has(id))nodes.set(id,new Node(id));return nodes.get(id);},createElement:tag=>new Node(tag),createTextNode:text=>({textContent:text}),addEventListener(){},querySelector:()=>new Node('aside')};
  const window=platform==='mac'?{webkit:{messageHandlers:{hud:{postMessage:m=>messages.push(m)}}}}:{chrome:{webview:{postMessage:m=>messages.push(m),addEventListener(){}}}};
  const context=vm.createContext({window,document,globalThis:{},setInterval(){},Event:class{constructor(type){this.type=type;}},console,innerWidth:900,innerHeight:600});
  vm.runInContext(model.replace('(globalThis)','(this)'),context);vm.runInContext(source,context);
  const $=id=>document.getElementById(id),buttons=()=>$('roster').children.filter(n=>n.tag==='button'),badge=()=>messages.filter(m=>m.op==='badge').at(-1)?.count;
  return {window,messages,$,buttons,badge};
}
test('Shepherdr mode lists spaces and tasks, badges needs-you, and sends only through a ready linked agent',()=>{
  const h=harness('mac');
  h.window.receive({type:'preferences',data:{shepherdrSupported:true,rosterMode:'shepherdr'}});
  assert.equal(h.$('modes').hidden,false);assert.equal(h.$('mode-shepherdr').getAttribute('aria-pressed'),'true');
  h.window.receive({type:'roster',data:{agents,machines:[],shepherdr:data}});
  assert.equal(h.buttons().length,5);assert.equal(h.badge(),1);
  assert.equal(h.buttons()[4].disabled,true,'a space with neither agent nor chat cannot be opened');
  h.window.receive({type:'visibility',data:{open:true}});h.window.receive({type:'output',data:{id:h.messages.filter(m=>m.op==='output').at(-1).id,provider:'claude',text:'earlier read'}});
  h.buttons()[3].click();assert.equal(h.$('title').textContent,'APP-2 · Merged one');
  assert.equal(h.messages.filter(m=>m.op==='output').at(-1).id,'shepherdr:APP-2/Agent');
  h.window.receive({type:'output',data:{id:'shepherdr:APP-2/Agent',provider:'shepherdr',text:'Agent\nMerged.'}});
  h.$('prompt').value='more';h.$('prompt').oninput();assert.equal(h.$('send').disabled,true,'a not-running agent is read only');assert.match(h.$('send-status').textContent,/read only/);
  h.buttons()[2].click();assert.equal(h.$('title').textContent,'APP-3 · Busy');assert.match(h.$('identity').textContent,/^app · Mac Studio · Working/);
  h.$('prompt').value='next step';h.$('prompt').oninput();assert.equal(h.$('send').disabled,true,'a working agent is refused');
  h.buttons()[0].click();h.$('prompt').value='next step';h.$('prompt').oninput();assert.equal(h.$('send').disabled,false);
  h.$('send').onclick();h.$('send').onclick();
  const prompts=h.messages.filter(m=>m.op==='prompt');assert.equal(prompts.length,1);assert.equal(prompts[0].id,'C');
});
test('a selected task follows its agent as it finishes and starts again, keeping the draft',()=>{
  const h=harness('mac'),task=(agent_id)=>({...data,tasks:[{id:'APP-3',title:'Busy',status:'work',place:'p:Mac:app',agent_id,chat:'APP-3/Agent'}]});
  h.window.receive({type:'preferences',data:{shepherdrSupported:true,rosterMode:'shepherdr'}});h.window.receive({type:'roster',data:{agents,machines:[],shepherdr:task('B')}});
  h.buttons()[1].click();h.$('prompt').value='keep me';h.$('prompt').oninput();
  h.window.receive({type:'roster',data:{agents:[agents[0]],machines:[],shepherdr:task(null)}});
  assert.equal(h.$('title').textContent,'APP-3 · Busy');assert.equal(h.$('prompt').value,'keep me');assert.equal(h.$('send').disabled,true);
  h.window.receive({type:'roster',data:{agents:[agents[0],agent('B2','idle')],machines:[],shepherdr:task('B2')}});
  assert.equal(h.$('title').textContent,'APP-3 · Busy');assert.equal(h.$('prompt').value,'keep me');assert.equal(h.$('send').disabled,false);
});
test('switching back to Herdr mode restores the plain agent roster and saves the choice',()=>{
  const h=harness('mac');
  h.window.receive({type:'preferences',data:{shepherdrSupported:true,rosterMode:'shepherdr'}});h.window.receive({type:'roster',data:{agents,machines:[],shepherdr:data}});
  h.$('mode-herdr').click();
  assert.deepEqual(h.messages.filter(m=>m.op==='preferences'&&m.rosterMode).map(m=>m.rosterMode),['herdr']);
  assert.equal(h.buttons().length,3);assert.equal(h.$('roster-label').textContent,'AGENTS');assert.equal(h.badge(),0);
});
test('hosts without Shepherdr support keep the plain roster and hide the switch',()=>{
  const h=harness('windows');
  h.window.receive({type:'preferences',data:{rosterMode:'shepherdr'}});h.window.receive({type:'roster',data:{agents,machines:[],shepherdr:data}});
  assert.equal(h.$('modes').hidden,true);assert.equal(h.buttons().length,3);
});
