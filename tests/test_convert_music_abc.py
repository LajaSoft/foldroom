import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('abc_converter', Path(__file__).parents[1] / 'tools/convert_music_abc.py')
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class MusicConversionTests(unittest.TestCase):
    def test_generated_score_matches_source(self):
        data = converter.compile_abc(converter.SOURCE.read_text())
        self.assertEqual(data, json.loads(converter.TARGET.read_text()))
        self.assertEqual([len(s['Vocal']) for s in data['sections']], [8, 16, 17, 8, 16, 8])
        self.assertEqual(data['sections'][3]['Ins'], data['sections'][5]['Ins'])
        self.assertEqual(data['sections'][1]['Vocal'][0], data['sections'][1]['Vocal'][4])

    def test_pitch_octave_key_and_accidental_reset(self):
        events = converter.parse_bar("_e4e4b4B4c'4d'4A4z4")[0]
        self.assertEqual([e['midi'] for e in events], [75, 75, 82, 70, 84, 86, 69, -1])
        self.assertEqual(converter.parse_bar('e32')[0][0]['midi'], 76)
        self.assertEqual(converter.parse_bar('=b32')[0][0]['midi'], 83)
        self.assertEqual(len(converter.parse_bar('Z4')), 4)

    def test_reject_malformed_or_unsupported_input(self):
        for bar in ('d4', 'd33', 'd0z32', '[df]32', 'd/2', 'd32?'):
            with self.subTest(bar=bar), self.assertRaises(ValueError):
                converter.parse_bar(bar)
        with self.assertRaises(ValueError):
            converter.compile_abc('K:C\n% intro\nV: Vocal\nd32|')
        with self.assertRaises(ValueError):
            converter.compile_abc('% intro\nV: Vocal\nd32|\nV: Ins\nZ2|')


if __name__ == '__main__':
    unittest.main()
