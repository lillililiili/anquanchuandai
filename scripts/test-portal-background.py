"""Source-based regressions for the business background export.

Run from the repository root: python scripts/test-portal-background.py
"""
import importlib.util
import json
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('portal_export', ROOT / 'scripts/extract-portal-design.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def transform(matrix, x, y):
    a, b, c, d, e, f = matrix
    return a*x+c*y+e, b*x+d*y+f


class BackgroundExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(exporter.s.SOURCE) as archive:
            document = json.loads(archive.read('document.json'))
            page = json.loads(archive.read(document['pages'][0]['_ref']+'.json'))
        cls.layers = {n['do_objectID']: n for n, _, _ in exporter.s.walk(page)}

    def fade_endpoints(self, layer_id):
        layer = self.layers[layer_id]
        gradient = next(f['gradient'] for f in layer['style']['fills'] if f['isEnabled'])
        self.assertEqual(gradient['stops'][0]['color']['alpha'], 0)
        self.assertGreater(gradient['stops'][-1]['color']['alpha'], .89)
        frame = layer['frame']
        matrix = exporter.layer_matrix(layer)
        return [transform(matrix, p[0]*frame['width'], p[1]*frame['height'])
                for p in (exporter.s.point(gradient['from']), exporter.s.point(gradient['to']))]

    def test_top_shade_fades_to_transparent_at_its_inner_edge(self):
        transparent, dark = self.fade_endpoints('15F83B84-63FF-4987-9D25-5618C2DA880E')
        self.assertAlmostEqual(transparent[1], 190)
        self.assertLess(dark[1], 27)
        self.assertGreater(transparent[1], dark[1])

    def test_bottom_shade_fades_toward_the_bottom_edge(self):
        transparent, dark = self.fade_endpoints('1B03DBD2-D381-4250-912F-803FF34E6B81')
        self.assertAlmostEqual(transparent[1], 950)
        self.assertGreater(dark[1], 1065)

    def test_background_has_original_images_and_valid_clip_geometry(self):
        root = ET.parse(ROOT / 'pc前台项目/public/assets/sketch/business-background.svg').getroot()
        ns = {'s': 'http://www.w3.org/2000/svg'}
        self.assertEqual(len(root.findall('.//s:image', ns)), 4)
        clips = root.findall('.//s:clipPath', ns)
        self.assertEqual(len(clips), 3)
        for clip in clips:
            self.assertEqual(len(clip), 1)
            self.assertIn(clip[0].tag.rsplit('}', 1)[-1], ('path', 'rect', 'ellipse'))
            self.assertIsNotNone(clip[0].get('transform'))


if __name__ == '__main__':
    unittest.main()
