#!/usr/bin/env python3
"""Structural tests: do not execute installers."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
bat = (root/'VeyraConnect_Kur.bat').read_bytes()
ps = (root/'src/VeyraConnect.ps1').read_text(encoding='utf-8')
assert bat.startswith(b'@echo off\r\n')
assert b'\n' not in bat.replace(b'\r\n',b'')
lines = bat.decode('utf-8').splitlines()
markers = [i for i,line in enumerate(lines) if line == ':__VEYRA_PS_PAYLOAD__']
assert len(markers) == 1 and markers[0] < 40
assert lines[markers[0]-1].startswith('exit /b ')
assert lines[markers[0]+1:] == ps.splitlines(), 'Embedded PowerShell differs from source'
assert '[string[]]$payload=$lines[($mark+1)..($lines.Length-1)]' in '\n'.join(lines[:40])
required = ['70d2c94147193cb915f9c6eb5144b8d404dacbcfa90bda2383b6b211afafa456',
            '3f3d0af999371cfa623bd641738a42785e107a9d829b38480ed3d942dafea28a',
            'https://github.com/hufrea/byedpi/releases/download/',
            'Verify-Hash', 'Start-And-TestProxy', 'Launch-Discord','Stop-OwnProxy',
            'Do-Uninstall', '127.0.0.1']
for x in required:
    assert x in ps, 'Missing '+x
for x in ['--ignore-certificate-errors','Set-MpPreference','Disable-NetAdapter',
          'New-NetFirewallRule','Stop-Process -Name cod','sc.exe delete']:
    assert x not in ps, 'Unexpected operation '+x
assert (root/'LICENSE_BYEDPI.txt').read_text(encoding='utf-8').startswith('MIT License')
assert (root/'README.md').exists()
print('PASS: BAT/PowerShell exact payload match, CRLF and pinned official archive SHA256')
print('Installer SHA256: '+hashlib.sha256(bat).hexdigest())
print('NOTE: structural test only; not a runtime Discord/CoD guarantee')
