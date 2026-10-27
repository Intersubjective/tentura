import pathlib
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'bump_client_version.sh'


class BumpClientVersionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        (root / 'scripts').mkdir()
        self.script = root / 'scripts' / SCRIPT.name
        shutil.copyfile(SCRIPT, self.script)
        self.pubspec = root / 'packages/client/pubspec.yaml'
        self.index = root / 'packages/client/web/index.html'
        self.index.parent.mkdir(parents=True)
        self.pubspec.write_text('name: tentura\nversion: 7.57.11+42\n')
        self.index.write_text('<script src="flutter_bootstrap.js?v=7.57.11" async></script>\n')

    def run_script(self, *args):
        return subprocess.run(['bash', str(self.script), *args], cwd='/',
                              capture_output=True, text=True)

    def assert_version(self, version):
        self.assertEqual(self.pubspec.read_text(), f'name: tentura\nversion: {version}\n')
        self.assertEqual(self.index.read_text(), f'<script src="flutter_bootstrap.js?v={version}" async></script>\n')

    def test_patch_and_repeat(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '7.57.11 -> 7.57.12')
        self.assert_version('7.57.12')
        self.assertEqual(self.run_script().returncode, 0)
        self.assert_version('7.57.13')

    def test_set(self):
        result = self.run_script('--set', '7.60.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_version('7.60.0')

    def test_minor(self):
        result = self.run_script('--minor')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_version('7.58.0')

    def test_mismatch_does_not_write_even_with_set(self):
        self.index.write_text('<script src="flutter_bootstrap.js?v=7.50.0"></script>\n')
        before = (self.pubspec.read_bytes(), self.index.read_bytes())
        result = self.run_script('--set', '7.60.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('mismatch', result.stderr.lower())
        self.assertEqual(before, (self.pubspec.read_bytes(), self.index.read_bytes()))

    def test_invalid_arguments_do_not_write(self):
        for args in [('--set',), ('--set', '7.60'), ('--set', '7.60.0+1'),
                     ('--minor', '--set', '7.60.0'), ('--unknown',)]:
            with self.subTest(args=args):
                before = (self.pubspec.read_bytes(), self.index.read_bytes())
                self.assertNotEqual(self.run_script(*args).returncode, 0)
                self.assertEqual(before, (self.pubspec.read_bytes(), self.index.read_bytes()))


if __name__ == '__main__':
    unittest.main()
