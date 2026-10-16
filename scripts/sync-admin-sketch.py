"""Copy verified Sketch exports into the independently served admin bundle.

Run extract-portal-design.py first when the Sketch file changes. This does not
render Sketch or generate replacements: exported bytes and source IDs are kept.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ('business-background.svg', 'filter-action.svg', 'navigation-active.svg',
         'navigation-idle.svg', 'navigation-title.svg', 'section-heading.svg')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = ROOT / 'pc前台项目/public/assets/sketch'
    target = ROOT / 'pc后台项目/public/assets/sketch'
    manifest_path = ROOT / 'shared/ui-spec/admin/assets.json'
    original = json.loads((ROOT / 'shared/ui-spec/portal/assets.json').read_text('utf-8'))
    manifest = json.loads(manifest_path.read_text('utf-8'))
    entries = {item['file']: item for item in manifest['assets']}
    assert manifest['sourceSha256'] == original['sourceSha256'], 'Sketch source changed'
    for name in FILES:
        expected = entries[name]['sha256']
        assert digest(source / name) == expected, f'Unreviewed source export: {name}'
        if not args.check:
            target.mkdir(parents=True, exist_ok=True)
            (target / name).write_bytes((source / name).read_bytes())
        assert digest(target / name) == expected, f'Admin asset differs: {name}'
    print(f'{len(FILES)} Sketch assets verified byte-for-byte; source {manifest["sourceSha256"]}')

if __name__ == '__main__':
    main()
