#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc scripts/fullscreen-probe.swift -o .build/fullscreen-probe
.build/fullscreen-probe
python3 - <<'PY'
import json
from pathlib import Path
p=Path('.evidence/fullscreen-probe.json')
d=json.loads(p.read_text())
for field in ['fullscreen','hudAboveFullscreen','overlapsFullscreen','fixtureStillFrontmost']:
    assert d.get(field) is True, (field,d)
print('PASS: H and panel above the fullscreen fixture; fixture stays frontmost')
PY
