const {test}=require('node:test'),assert=require('node:assert/strict');
const {sorted,alerts,parse}=require('../Sources/HerdrHUD/Resources/model.js');
const row=(id,status)=>({id,terminal_id:id,agent_status:status,online:true});
test('attention before working before read idle',()=>assert.deepEqual(sorted([row('a','idle'),row('b','working'),row('c','blocked')],new Set()).map(a=>a.id),['c','b','a']));
test('status alerts exclude baseline, replacements, and offline recovery',()=>{assert.equal(alerts([],[row('a','done')]).length,0);assert.equal(alerts([row('a','working')],[row('a','done')]).length,1);assert.equal(alerts([row('a','working')],[{...row('a','done'),terminal_id:'new'}]).length,0);assert.equal(alerts([{...row('a','working'),online:false}],[row('a','done')]).length,0)});
test('provider fallback retains all text',()=>assert.equal(parse('plain text','claude').text,'plain text'));
test('Codex composer removed only with model footer',()=>{const p=parse('• Hello\n\n› Ask Codex to do anything\n  gpt-6-astra ultra · ~/repo','codex');assert.equal(p.model,'gpt-6-astra');assert.equal(p.reasoning,'ultra');assert.equal(p.blocks[0].text,'Hello');assert.equal(parse('quote gpt-6-astra\n› Keep this','codex').blocks.at(-1).text,'Keep this')});
test('Codex default reasoning footer and composer do not become a fake user message',()=>{
  const text='› Summarize the fixture\n\n• First fixture response.\n\n› Explain the fixture\n\n• Second fixture response.\n\n  done 1:00 PM\n\n› Ask Codex to do anything\n\n  gpt-6-astra default · ~\\Documents\\project · Example task  \n';
  const parsed=parse(text,'codex');
  assert.equal(parsed.model,'gpt-6-astra');assert.equal(parsed.reasoning,'default');
  assert.deepEqual(parsed.blocks.filter(b=>b.kind==='prompt').map(b=>b.text),['Summarize the fixture','Explain the fixture']);
  assert.match(parsed.blocks.at(-1).text,/Second fixture response\./);
  assert.doesNotMatch(parsed.text,/Ask Codex to do anything|Example task|~\\Documents/);
  assert.equal(parse('› Ask Codex to do anything\n\n• What would you like to build?','codex').blocks[0].text,'Ask Codex to do anything');
});
test('tool blocks fold and code markers do not invent messages',()=>{const p=parse('• Ran test\n  output\n• Result\n```\n› not a prompt\n```','codex');assert.equal(p.blocks[0].kind,'tool');assert.equal(p.blocks.length,2);assert.match(p.blocks[1].text,/not a prompt/)});
