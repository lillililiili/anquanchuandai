"""Re-read the approved Sketch modal artboard and export its actual ornaments.

No generated artwork, icon substitution, or changes to the portal assets.
The evidence records native layer values; CSS adaptations are documented separately.
"""
from pathlib import Path
import copy, hashlib, importlib.util, json, sys, zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('portal_source', ROOT / 'scripts/extract-portal-design.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)
SKETCH = source.s.SOURCE
OUT = ROOT / 'shared/ui-spec/admin'
ASSETS = ROOT / 'pc后台项目/public/assets/sketch'
BOARD = '57889E44-04D1-4D74-B94F-4C1C42F427E5'
LAYERS = {
    'backdrop': '94AB0521-8770-4448-8ED4-975DAD8791EF',
    'outer': 'AD3EBC59-247B-4D9C-86E0-F0AC25A0692E',
    'glow': '65B57465-E9BE-440B-AB42-47BBC1163018',
    'surface': '80ACE0FF-408D-40D3-B5C1-3630C85B306A',
    'heading': '0DCB0708-0F92-4B42-A514-DA55020D1A84',
    'close': '20DBDFC3-8850-4F87-AD2A-9CE775137686',
    'footer': '525E1472-7423-4586-9CBC-4EAB4E57E716',
    'primary': '6D318D67-CA34-4DF5-8126-1FB7B325207C',
    'secondary': 'A93BB3AF-68B2-4A04-BC1E-C79D1F941917',
    'input': 'CD166CDC-1C0D-4B19-9385-8A06E527D934',
    'label': 'C4B96BEE-CAAF-4C7C-958C-AA312CE0434D',
    'inputText': '5FEA41B6-4168-4FB1-AD8F-6007608BF01E',
    'detailText': 'DA3D0A3E-0EBB-473B-B9BC-35C2B2C03687',
}

def main():
    digest = hashlib.sha256(SKETCH.read_bytes()).hexdigest()
    if digest != source.s.EXPECTED:
        raise SystemExit('Sketch has changed; review it before exporting.')
    with zipfile.ZipFile(SKETCH) as archive:
        doc = json.loads(archive.read('document.json'))
        page = json.loads(archive.read(doc['pages'][0]['_ref'] + '.json'))
        board = next(n for n in page['layers'] if n['do_objectID'] == BOARD)
        index = {n['do_objectID']: n for n, _, visible in source.s.walk(board) if visible}
        renderer = source.Exporter(archive)
        ASSETS.mkdir(parents=True, exist_ok=True)
        assets = {}

        def export(name, node):
            svg = renderer.svg(node)
            (ASSETS / name).write_text(svg, 'utf-8')
            assets[name] = {'sourceId': node['do_objectID'], 'sha256': hashlib.sha256(svg.encode()).hexdigest()}

        export('dialog-close.svg', index[LAYERS['close']])
        # Keep all three source paths and their original spacing/stroke widths.
        decoration = copy.deepcopy(index['058DDB4E-9A77-4342-A319-3B2B9B8D2574'])
        decoration['layers'] = decoration['layers'][1:]
        left = min(n['frame']['x'] for n in decoration['layers'])
        right = max(n['frame']['x'] + n['frame']['width'] for n in decoration['layers'])
        for n in decoration['layers']:
            n['frame']['x'] -= left
        decoration['frame'].update(x=0, y=0, width=right-left, height=15.94637942680558)
        export('dialog-heading-marks.svg', decoration)
        export('dialog-primary.svg', index[LAYERS['primary']])
        evidence = {
            'source': str(SKETCH), 'sha256': digest, 'artboardId': BOARD,
            'artboardName': board['name'], 'artboardFrame': board['frame'],
            'layers': {name: index[id] for name, id in LAYERS.items()},
            'assets': assets,
            'note': 'Native JSON parameters and paths. Not a native Sketch render; responsive dimensions are documented in dialogs.md.',
        }
        (OUT / 'dialog-reference.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2), 'utf-8')
        print(json.dumps({'artboard': board['name'], 'assets': list(assets), 'layers': len(LAYERS)}, ensure_ascii=False))

if __name__ == '__main__':
    main()
