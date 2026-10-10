#!/usr/bin/env python3
from pathlib import Path
import shutil, plistlib

root=Path(__file__).resolve().parents[1]
source=root/'OneShot'
dest=root/'Enhanced'
(dest/'LocationApp'/'Resources').mkdir(parents=True,exist_ok=True)
for rel in ['EmailHook.m','Makefile','ZZNo2TheftOnDemandGPS.plist','control','LocationApp/main.m','LocationApp/Makefile','LocationApp/control','LocationApp/Resources/Info.plist']:
    p=dest/rel
    p.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source/rel,p)

print('Copied only known-good on-demand location components')
