#!/usr/bin/env python3
"""Check only this HUD's show/hide/open/close controls; leave H visible."""
import json
from pathlib import Path
import subprocess
import time
root = Path.home()
exe = root/'Applications/Herdr HUD.app/Contents/MacOS/HerdrHUD'
diagnostic = root/'Library/Application Support/Herdr HUD/diagnostics.json'
checks = []
for command, visible, opened in [('hide',False,False),('show',True,False),('open',True,True),('close',True,False)]:
    subprocess.run([str(exe),'--'+command],check=True)
    end=time.monotonic()+10
    while time.monotonic()<end:
        data=json.loads(diagnostic.read_text())
        if data['visible']==visible and data['panelOpen']==opened: break
        time.sleep(.1)
    else: raise SystemExit('HUD state did not match '+command)
    checks.append({'command':command,'passed':True})
path=root/'Projects/herdr-hud-desktop/.evidence/visibility.json'
path.parent.mkdir(exist_ok=True)
path.write_text(json.dumps(checks,indent=2)+'\n')
print('PASS: hide, show, open, close; H is visible')
