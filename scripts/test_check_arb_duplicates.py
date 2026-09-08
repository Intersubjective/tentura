import json
from pathlib import Path
import tempfile
import unittest

from check_arb_duplicates import check, unique_object


class ArbDuplicatesTest(unittest.TestCase):
    def test_rejects_equal_and_different_duplicate_values(self):
        for source in ('{"label":"same","label":"same"}', '{"label":1,"label":2}'):
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "label"):
                json.loads(source, object_pairs_hook=unique_object)

    def test_rejects_nested_metadata_and_escaped_equivalent_keys(self):
        for source in (
            '{"@label":{"placeholders":{"name":{"type":"String","type":"String"}}}}',
            r'{"label":1,"\u006cabel":1}',
        ):
            with self.subTest(source=source), self.assertRaises(ValueError):
                json.loads(source, object_pairs_hook=unique_object)

    def test_same_key_in_separate_objects_is_valid(self):
        json.loads('{"a":{"type":1},"b":{"type":2}}', object_pairs_hook=unique_object)

    def test_reports_filename_and_continues_across_files(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ("en.arb", "ru.arb")]
            for path in paths:
                path.write_text('{"label":1,"label":1}', encoding="utf-8")
            errors = check(paths)
            self.assertEqual(len(errors), 2)
            for path, error in zip(paths, errors):
                self.assertIn(str(path), error)


if __name__ == "__main__":
    unittest.main()
