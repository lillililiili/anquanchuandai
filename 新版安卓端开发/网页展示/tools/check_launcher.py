"""Regression check for the actual Windows batch launcher (server must be running)."""
from pathlib import Path
import subprocess, urllib.request
ROOT=Path(__file__).resolve().parents[1]
for name in ['打开安卓演示.cmd','停止安卓演示.cmd']:
    raw=(ROOT/name).read_bytes()
    assert not raw.startswith(b'\xef\xbb\xbf'), f'{name}: CMD must not have a UTF-8 BOM'
    assert b'\n' not in raw.replace(b'\r\n',b''), f'{name}: CMD requires CRLF'
with urllib.request.urlopen('http://127.0.0.1:18766/__preview_health',timeout=5) as response:
    assert response.read()==b'rolling-android-preview'
result=subprocess.run(['cmd.exe','/d','/c','打开安卓演示.cmd'],cwd=ROOT,capture_output=True,timeout=15)
assert result.returncode==0, f'CMD failed: {result.stdout!r} {result.stderr!r}'
assert not result.stderr, f'CMD error output: {result.stderr!r}'
with urllib.request.urlopen('http://127.0.0.1:18766/',timeout=5) as response:
    assert response.status==200 and b'flutter_bootstrap.js' in response.read()
print('PASS: CRLF batch files, actual CMD entry, existing-service reuse and HTML delivery')
