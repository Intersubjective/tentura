"""affected_tests selects the direct importer of every changed lib file."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LIBS = ("lib/a.dart", "lib/b.dart", "lib/c.dart")


class AffectedTestsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="tentura-affected-")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        (self.repo / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/run_tests.sh", self.repo / "scripts/run_tests.sh")
        self.write("bin/git", "#!/bin/sh\n" + "".join(
            f"[ \"$1\" = diff ] && echo packages/client/{lib}\n" for lib in LIBS))
        for name in "abc":
            self.write(f"packages/client/lib/{name}.dart", "library;\n")
            self.write(
                f"packages/client/test/{name}_test.dart",
                f"import 'package:tentura/{name}.dart';\n")
        self.write("packages/client/test/other_test.dart", "import 'package:tentura/z.dart';\n")

    def write(self, path, contents):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents)
        target.chmod(0o755)

    def test_each_changed_lib_selects_its_importer(self):
        result = subprocess.run(
            ["bash", str(self.repo / "scripts/run_tests.sh"), "--dry-run", "client-affected"],
            cwd=self.repo, text=True, capture_output=True, timeout=30,
            env={**os.environ, "PATH": f"{self.repo / 'bin'}:{os.environ['PATH']}"},
        )
        output = result.stdout + result.stderr
        for name in "abc":
            self.assertIn(f"test/{name}_test.dart", output, output)
        self.assertNotIn("other_test.dart", output)


if __name__ == "__main__":
    unittest.main()
