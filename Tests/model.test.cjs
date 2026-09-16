const {test}=require('node:test'),assert=require('node:assert/strict');
const {sorted,alerts,parse}=require('../Sources/HerdrHUD/Resources/model.js');
const row=(id,status)=>({id,terminal_id:id,agent_status:status,online:true});
test('attention before working before read idle',()=>assert.deepEqual(sorted([row('a','idle'),row('b','working'),row('c','blocked')],new Set()).map(a=>a.id),['c','b','a']));
test('status alerts exclude baseline, replacements, and offline recovery',()=>{assert.equal(alerts([],[row('a','done')]).length,0);assert.equal(alerts([row('a','working')],[row('a','done')]).length,1);assert.equal(alerts([row('a','working')],[{...row('a','done'),terminal_id:'new'}]).length,0);assert.equal(alerts([{...row('a','working'),online:false}],[row('a','done')]).length,0)});
test('provider fallback retains all text',()=>assert.equal(parse('plain text','claude').text,'plain text'));
test('Codex composer removed only with model footer',()=>{const p=parse('• Hello\n\n› Ask Codex to do anything\n  gpt-6-astra ultra · ~/repo','codex');assert.equal(p.model,'gpt-6-astra');assert.equal(p.reasoning,'ultra');assert.equal(p.blocks[0].text,'Hello');assert.equal(parse('quote gpt-6-astra\n› Keep this','codex').blocks.at(-1).text,'Keep this')});
test('tool blocks fold and code markers do not invent messages',()=>{const p=parse('• Ran test\n  output\n• Result\n```\n› not a prompt\n```','codex');assert.equal(p.blocks[0].kind,'tool');assert.equal(p.blocks.length,2);assert.match(p.blocks[1].text,/not a prompt/)});
test('Claude Code transcript splits into prompt, reply, tool and status blocks',()=>{
  const screen=[' ▐▛███▛█   Claude Code v2.1.273','▝▜██████▀  Fable 5.1 · Claude Max','  ▝▝ ▝▝    C:\\Users\\me','','❯ Hey','','● Hey! What are you working on today?','  Second line.','','✻ Worked for 1s · done 9:31 PM','','● Bash(ls)','  ⎿  a.txt','     b.txt','','● Done.','','','','','','','──────────','❯ ','──────────','  ⏵⏵ auto mode on'].join('\n');
  const p=parse(screen,'claude');
  assert.equal(p.model,'Fable 5.1');assert.equal(p.reasoning,'Claude Max');
  assert.deepEqual(p.blocks.map(b=>b.kind),['prompt','reply','status','tool','reply']);
  assert.equal(p.blocks[0].text,'Hey');assert.equal(p.blocks[1].text,'Hey! What are you working on today?\nSecond line.');
  assert.equal(p.blocks[3].text,'Bash(ls)\n  ⎿  a.txt\n     b.txt');
  assert.ok(!p.text.includes('auto mode on'),'prompt box removed');assert.ok(!/\n{3}/.test(p.text),'blank runs squeezed');
});
test('Claude Code fenced code does not start blocks',()=>{const p=parse('● Look:\n```\n❯ not a prompt\n```','claude');assert.equal(p.blocks.length,1);assert.match(p.blocks[0].text,/not a prompt/)});
