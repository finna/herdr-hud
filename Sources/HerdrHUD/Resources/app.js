'use strict';
const $=id=>document.getElementById(id), post=data=>window.webkit.messageHandlers.hud.postMessage(data);
let agents=[],selected='',opened=false,mode='chat',filter='',reading=false,sending=false,requestSequence=0,lastOutput='',lastRendered='',selectionEpoch=0;
let baseline=false,unread=new Set(),drafts=new Map(),outputs=new Map(),since=new Map(),uncertain=new Set(),promptByRequest=new Map();
function request(op,extra={}){const requestID=`${Date.now()}-${++requestSequence}`;post({op,requestID,...extra});return requestID;}
function active(){return agents.find(a=>a.id===selected);}
function name(a){return a.tab_label||a.name||a.pane_id||'Agent';}
function el(tag,text,cls){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;}
function notice(text){$('notice').hidden=!text;$('notice').textContent=text;}
function badge(){post({op:'badge',count:agents.filter(a=>a.agent_status==='blocked'||unread.has(a.id)).length});}
function renderRoster(){
  $('count').textContent=agents.length;const roster=$('roster'),scroll=roster.scrollTop;
  const items=HUDModel.sorted(agents,unread).filter(a=>`${name(a)} ${a.workspace_label} ${a.machine_label} ${a.agent}`.toLowerCase().includes(filter));
  roster.replaceChildren(...items.map(a=>{const button=el('button',undefined,'agent'+(a.id===selected?' selected':'')+(!a.online?' offline':''));button.setAttribute('aria-pressed',String(a.id===selected));
    const title=el('div',undefined,'agent-title');title.append(el('span',undefined,'dot '+(a.agent_status==='working'?'busy':a.agent_status==='blocked'||unread.has(a.id)?'attention':'')),el('span',name(a)));button.append(title);
    const meta=el('div',undefined,'agent-meta');meta.append(el('div',a.workspace_label||a.workspace_id),el('div',a.machine_label+' · '+(a.agent||'agent')),el('div',a.online?a.agent_status:'Offline','agent-state'));button.append(meta);const metadata=HUDModel.parse(outputs.get(a.id)?.text||'',a.agent);button.title=metadata.model?`${metadata.model} ${metadata.reasoning}`:a.pane_id;button.onclick=()=>select(a.id);return button;}));
  if(!items.length)roster.append(el('p',agents.length?'No matching agents.':'No agents found. Start an agent in Herdr.','empty'));roster.scrollTop=scroll;
}
function select(id){
  drafts.set(selected,$('prompt').value);selected=id;selectionEpoch++;lastRendered='';$('prompt').value=drafts.get(id)||'';
  lastOutput=outputs.get(id)?.text||'';renderRoster();renderHeader();renderOutput();read();
}
function renderHeader(){
  const a=active();$('title').textContent=a?name(a):'Select an agent';$('identity').textContent=a?`${a.workspace_label} · ${a.machine_label} · ${a.agent}`:'Your configured Herdr machines appear automatically';
  const state=a?.agent_status||'';const busy=state==='working';$('working').hidden=!busy;
  if(busy&&!since.has(a.id))since.set(a.id,Date.now());
  $('send').disabled=!a?.online||!['idle','done'].includes(state)||sending||uncertain.has(selected)||!$('prompt').value.trim();
  $('prompt').disabled=!a;$('chat').disabled=a?.agent!=='codex';
  $('send-status').textContent=sending?'Sending once…':uncertain.has(selected)?'Delivery uncertain. Inspect this agent in Herdr before sending again.':!a?'Choose an agent to get started.':!a.online?'Machine offline. Your draft is retained.':state==='blocked'?'Needs your input in Herdr. Native approvals remain in its terminal.':busy?'Agent is working. You can draft the next prompt here.':['idle','done'].includes(state)?'Ready for your next prompt.':'Agent state is unknown. Sending is disabled.';
  $('reconcile').hidden=!uncertain.has(selected);
}
function inline(text,parent){ // No terminal text is ever interpreted as HTML.
  for(const part of text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g)){if(part.startsWith('**')&&part.endsWith('**'))parent.append(el('strong',part.slice(2,-2)));else if(part.startsWith('`')&&part.endsWith('`'))parent.append(el('code',part.slice(1,-1)));else parent.append(document.createTextNode(part));}
}
function renderOutput(){
  const a=active(),out=$('output'),data=HUDModel.parse(lastOutput,a?.agent||'');const terminal=mode==='terminal'||a?.agent!=='codex';
  const signature=JSON.stringify([selected,lastOutput,terminal]);if(signature===lastRendered)return;const wasBottom=out.scrollHeight-out.scrollTop-out.clientHeight<70,scroll=out.scrollTop;const first=!lastRendered;lastRendered=signature;
  const expanded=new Set([...out.querySelectorAll('details[open]')].map(n=>n.dataset.key));out.replaceChildren();
  if(!lastOutput)out.append(el('p',a?'Loading recent output…':'Select an agent to read its recent output.','empty'));
  else if(terminal||!data.blocks.length)out.append(el('pre',data.text));
  else data.blocks.forEach((block,index)=>{const node=el('div',undefined,'block '+block.kind);
    if(block.kind==='tool'){const detail=el('details');detail.dataset.key=block.kind+block.text.split('\n')[0]+index;detail.open=expanded.has(detail.dataset.key);detail.append(el('summary',block.text.split('\n')[0]),el('pre',block.text));node.append(detail);}
    else{if(block.kind==='prompt')node.append(el('div','You','block-label'));else if(block.kind==='reply')node.append(el('div',data.model||a.agent,'block-label'));inline(block.text,node);}out.append(node);});
  if(data.model){$('title').title=`${data.model} ${data.reasoning}`;for(const button of $('roster').children)if(button.getAttribute('aria-pressed')==='true')button.title=`${data.model} ${data.reasoning}`;}
  $('chat').setAttribute('aria-pressed',String(!terminal));$('terminal').setAttribute('aria-pressed',String(terminal));
  out.scrollTop=first||wasBottom?out.scrollHeight:scroll;
}
function read(){if(!opened||reading||!active()?.online)return;reading=true;request('output',{id:selected});}
function send(){if($('send').disabled)return;const id=selected,message=$('prompt').value;sending=true;notice('');const requestID=request('prompt',{id,message});promptByRequest.set(requestID,{id,message});renderHeader();}
window.receive=({type,data})=>{
  if(type==='roster'){
    const before=agents;agents=data.agents||[];
    if(baseline)for(const a of agents){const old=before.find(b=>b.id===a.id);if(old&&a.online&&old.online&&old.agent_status!==a.agent_status)unread.add(a.id);}
    const updates=baseline?HUDModel.alerts(before,agents):[];baseline=true;
    for(const a of agents){if(a.agent_status==='working'&&!since.has(a.id))since.set(a.id,Date.now());if(a.agent_status!=='working')since.delete(a.id);}
    const valid=new Set(agents.map(a=>a.id));unread=new Set([...unread].filter(id=>valid.has(id)));
    if(updates.length&&!opened){const a=updates[0];request('alertPreview',{id:a.id,title:name(a)+(a.agent_status==='blocked'?' needs input':' finished')});}
    $('machines').replaceChildren(...(data.machines||[]).map(m=>{const node=el('span',undefined,'machine');node.append(el('span',undefined,'dot '+(m.online?'online':'')),document.createTextNode(`${m.label} · ${m.online?`${m.count} agents`:'offline'}`));node.title=m.error||'';return node;}));
    $('connection').textContent=`${agents.filter(a=>a.online).length} agents online · updates every 3s`;
    if(data.discoveryError)notice('Herdr setup: '+data.discoveryError);
    if(!selected&&agents.length)select(agents[0].id);renderRoster();renderHeader();badge();read();
  }else if(type==='visibility'){opened=data.open;if(opened){renderHeader();read();}}
  else if(type==='resetBaseline'){baseline=false;}
  else if(type==='select'){select(data.id);}
  else if(type==='alertPreview'){if(!opened){const parsed=HUDModel.parse(data.text,data.provider),reply=parsed.blocks.filter(x=>x.kind==='reply').at(-1)?.text||'';post({op:'alert',id:data.id,title:data.title,preview:reply.replace(/\s+/g,' ').slice(0,200)||'Click to read the latest output'});}}
  else if(type==='output'){
    reading=false;if(data.error){if(data.id===selected)notice(data.error);return;}
    outputs.set(data.id,data);if(data.id!==selected){read();return;}
    lastOutput=data.text;notice('');if(opened){unread.delete(selected);badge();}renderOutput();renderRoster();
  }else if(type==='prompt'){
    const pending=promptByRequest.get(data.requestID);if(!pending)return;promptByRequest.delete(data.requestID);sending=false;
    if(data.error){notice(data.error);if(/uncertain/i.test(data.error))uncertain.add(pending.id);}
    else{if(selected===pending.id&&$('prompt').value===pending.message)$('prompt').value='';if(drafts.get(pending.id)===pending.message)drafts.delete(pending.id);notice('Prompt sent.');request('refresh');}renderHeader();
  }else if(type==='preferences'){if(data.rosterWidth>=155)document.querySelector('aside').style.width=data.rosterWidth+'px';mode=data.mode||'chat';}
  else if(type==='notice'){notice(data.message);}
};
$('refresh').onclick=()=>request('refresh');$('close').onclick=()=>request('close');$('hide').onclick=()=>request('hide');$('send').onclick=send;
$('reconcile').onclick=()=>{uncertain.delete(selected);notice('');renderHeader();};
$('search').oninput=()=>{filter=$('search').value.toLowerCase();renderRoster();};
$('prompt').oninput=()=>{drafts.set(selected,$('prompt').value);renderHeader();};
$('prompt').onkeydown=e=>{if(e.key==='Enter'&&(e.metaKey||e.ctrlKey)){e.preventDefault();send();}};
for(const view of ['chat','terminal'])$(view).onclick=()=>{mode=view;request('preferences',{mode});lastRendered='';renderOutput();};
const divider=$('divider');divider.onpointerdown=e=>{divider.setPointerCapture(e.pointerId);};divider.onpointermove=e=>{if(divider.hasPointerCapture(e.pointerId)){document.querySelector('aside').style.width=Math.min(Math.max(e.clientX,155),innerWidth*.42)+'px';}};
divider.onpointerup=()=>request('preferences',{rosterWidth:document.querySelector('aside').offsetWidth});
divider.onkeydown=e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();const aside=document.querySelector('aside');aside.style.width=Math.min(Math.max(aside.offsetWidth+(e.key==='ArrowLeft'?-15:15),155),innerWidth*.42)+'px';request('preferences',{rosterWidth:aside.offsetWidth});}};
setInterval(()=>{const a=active();if(a?.agent_status==='working'){const seconds=Math.max(0,Math.floor((Date.now()-(since.get(a.id)||Date.now()))/1000));$('work-text').textContent=`Working · ${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')} observed`; }},1000);
request('ready');
// Read-only integration check used by --verify-ui; never presses Send.
window.verifyControls=async()=>{
  const saved={selected,filter,mode,draft:$('prompt').value,drafts:new Map(drafts)},results={};
  const wait=async predicate=>{const end=Date.now()+22000;while(!predicate()){if(Date.now()>end)throw Error('Timed out waiting for agent output');await new Promise(r=>setTimeout(r,100));}};
  try{
    const local=agents.find(a=>a.machine_id==='local'&&a.online),remote=agents.find(a=>a.machine_id!=='local'&&a.online);
    if(!local||!remote)throw Error('This check requires one local and one remote agent');
    select(local.id);await wait(()=>outputs.has(local.id)&&!reading);results.localOutput=outputs.get(local.id).text.length>0;
    $('prompt').value='HUD verification draft — never submitted';$('prompt').dispatchEvent(new Event('input'));
    select(remote.id);await wait(()=>outputs.has(remote.id)&&!reading);results.remoteOutput=outputs.get(remote.id).text.length>0;
    select(local.id);results.draftPreserved=$('prompt').value==='HUD verification draft — never submitted';
    $('terminal').click();results.terminalView=$('output').querySelector('pre')!==null;
    $('chat').click();results.chatView=$('chat').getAttribute('aria-pressed')==='true';
    $('search').value='a-nonexistent-agent-filter';$('search').dispatchEvent(new Event('input'));results.searchFilters=$('roster').querySelectorAll('.agent').length===0;
    const test=el('div');inline('<img src=x onerror=alert(1)>',test);results.transcriptIsText=test.querySelector('img')===null&&test.textContent.includes('<img');
    results.layoutFits=document.body.scrollWidth<=innerWidth&&document.body.scrollHeight<=innerHeight;
    results.pass=Object.values(results).every(Boolean);return results;
  }finally{drafts=new Map(saved.drafts);filter=saved.filter;mode=saved.mode;$('search').value=saved.filter;select(saved.selected);$('prompt').value=saved.draft;drafts=new Map(saved.drafts);request('preferences',{mode});renderHeader();renderOutput();}
};
