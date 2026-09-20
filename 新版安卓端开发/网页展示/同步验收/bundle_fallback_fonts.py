"""Bundle the current Flutter engine's Simplified Chinese fallback subsets."""
import concurrent.futures, hashlib, json, re, urllib.request
from pathlib import Path

project = Path(__file__).resolve().parents[3]
target = project / 'android代码/melhat_android-main/web/fonts/fallback'
engine = Path('C:/melhat-runtime/flutter/bin/cache/flutter_web_sdk/lib/_engine/engine/font_fallback_data.dart')
names = sorted(set(re.findall(r"'(notosanssc/[^']+\.woff2)'", engine.read_text('utf-8'))))
assert names, 'Flutter fallback font list is missing'

def fetch(name):
    path = target / name
    if not path.exists():
        data = urllib.request.urlopen('https://fonts.gstatic.com/s/' + name, timeout=45).read()
        assert data[:4] == b'wOF2', 'Invalid font: ' + name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return {'file': name, 'source': 'https://fonts.gstatic.com/s/' + name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    entries = list(pool.map(fetch, names))
(target / 'sources.json').write_text(json.dumps(entries, indent=2), 'utf-8')
print(json.dumps({'fontSubsets': len(entries), 'totalBytes': sum((target/e['file']).stat().st_size for e in entries)}))
