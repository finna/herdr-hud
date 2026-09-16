/* MIT — transcript parser and roster semantics shared by desktop shells. */
(function(root){
  function priority(a,unread){return a.agent_status==='blocked'||unread.has(a.id)?0:a.agent_status==='working'?1:2;}
  function sorted(agents,unread){return agents.map((agent,index)=>({agent,index})).sort((a,b)=>priority(a.agent,unread)-priority(b.agent,unread)||a.index-b.index).map(x=>x.agent);}
  function identity(a){return JSON.stringify([a.id,a.terminal_id,a.agent_session||null]);}
  function alerts(previous,current){const old=new Map(previous.map(a=>[a.id,a]));return current.filter(a=>{const b=old.get(a.id);return a.online&&b?.online&&identity(a)===identity(b)&&((a.agent_status==='blocked'&&b.agent_status!=='blocked')||(b.agent_status==='working'&&['idle','done'].includes(a.agent_status)));});}
  function supportsChat(provider){return provider==='codex'||provider==='claude';}
  const squeeze=text=>text.replace(/[ \t]+$/gm,'').replace(/\n{3,}/g,'\n\n').trimEnd();
  function withoutPromptBox(lines){
    for(let i=lines.length-1;i>=Math.max(0,lines.length-12);i--){
      if(!/^\s*[─━]{4,}/.test(lines[i]))continue;
      let top=i;for(let j=i-1;j>=Math.max(0,i-4);j--)if(/^\s*[─━]{4,}/.test(lines[j])){top=j;break;}
      return lines.slice(0,top);
    }
    return lines;
  }
  function parseClaude(text){
    const lines=withoutPromptBox(text.replace(/\r/g,'').split('\n'));
    let model='',reasoning='';
    for(const line of lines.slice(0,8)){const banner=/^[▐▛▝▜█▀\s]+([A-Za-z][\w.-]* [\d.]+)\s+·\s+(.+?)\s*$/.exec(line);if(banner){model=banner[1];reasoning=banner[2];break;}}
    let kind='context',body=[],fenced=false,blocks=[];
    const flush=()=>{const raw=body.join('\n'),text=squeeze(kind==='tool'?raw:raw.replace(/^ {2}/gm,'')).trim();if(text)blocks.push({kind,text});body=[];};
    for(const line of lines){
      const marker=!fenced&&/^([❯>●⏺])(?: |$)(.*)/.exec(line),status=!fenced&&/^\s*[✻✽✶✳✢·*] (.+ for \d+(?:\.\d+)?(?:s|m|h|ms).*)$/.exec(line);
      if(marker||status){flush();
        if(status){kind='status';body=[status[1].trim()];}
        else if(/[❯>]/.test(marker[1])){kind='prompt';body=[marker[2]];}
        else if(/^How is Claude doing this session/.test(marker[2])){kind='status';body=[marker[2]];}
        else{kind=/^[A-Z][A-Za-z_-]*\(/.test(marker[2])?'tool':'reply';body=[marker[2]];}
      }else body.push(line);
      if(line.trimStart().startsWith('```'))fenced=!fenced;
    }
    flush();
    if(blocks[0]?.kind==='context'&&/Claude Code v\d/.test(blocks[0].text))blocks.shift();
    return {text:squeeze(lines.join('\n')),model,reasoning,blocks};
  }
  function parse(text,provider){
    if(provider==='claude')return parseClaude(text);
    let model='',reasoning='',lines=text.trimEnd().split('\n');
    if(provider!=='codex')return {text,model,reasoning,blocks:[]};
    const footer=/^\s*(gpt-[\w.-]+|o[134](?:-[\w.-]+)?|codex-[\w.-]+)(?:\s+(minimal|low|medium|high|xhigh|max|ultra))?\s+[·|]\s*.+$/.exec(lines.at(-1)||'');
    if(footer){for(let i=lines.length-2;i>=Math.max(0,lines.length-14);i--){if(/^\s*[›❯»](?:\s|$)/.test(lines[i])){model=footer[1];reasoning=footer[2]||'';lines=lines.slice(0,i);break;}if(lines[i].trim()&&(!lines[i].startsWith('  ')||/^\s*•/.test(lines[i])))break;}}
    let kind='context',body=[],fenced=false,blocks=[];
    const flush=()=>{const text=body.join('\n').trim();if(text)blocks.push({kind,text});body=[];};
    for(const line of lines){const marker=!fenced&&/^([›❯»•●])(?: |$)(.*)/.exec(line),status=!fenced&&/^[─━]+ (Worked for .+|Conversation recap.*)/.exec(line);
      if(marker||status){flush();if(status){kind='status';body=[line.replace(/[─━]/g,'').trim()];}else{kind=/[›❯»]/.test(marker[1])?'prompt':/^(Ran |Explored\b|Viewed Image\b|Searched (for|the web)|Edited .+\(\+|Added .+\(\+|Deleted .+\(-|Interacted with background terminal\b)/.test(marker[2])?'tool':'reply';body=[marker[2]];}}
      else body.push(line);if(line.trimStart().startsWith('```'))fenced=!fenced;
    }flush();return {text:lines.join('\n').trimEnd(),model,reasoning,blocks};
  }
  const api={sorted,alerts,parse,identity,supportsChat};if(typeof module!=='undefined')module.exports=api;else root.HUDModel=api;
})(globalThis);
