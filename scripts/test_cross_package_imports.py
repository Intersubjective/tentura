"""CLI contracts for keeping client and server tests independently runnable.

Run with: python3 -m pytest scripts/test_cross_package_imports.py
Fixture repositories preserve the script-relative root convention used by
check_repo_files_tags.py; no Dart compiler or generated files are needed.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parent.parent
GUARD = "check_cross_package_imports.py"


def write(root, path, source):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source, encoding="utf-8")
    return target


def run_guard(root):
    script = ROOT / "scripts" / GUARD
    assert script.is_file(), (
        "The cross-package import guard CLI is missing; package isolation "
        "cannot be checked before code generation."
    )
    if root != ROOT:
        destination = root / "scripts" / GUARD
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(script, destination)
    return subprocess.run(
        [sys.executable, str(root / "scripts" / GUARD)],
        cwd=root, capture_output=True, text=True, timeout=30,
    )


def assert_rejected(result, path, line):
    output = result.stdout + result.stderr
    assert result.returncode != 0, f"Forbidden dependency was accepted: {output}"
    assert f"{path}:{line}" in output, output
    assert "Traceback" not in output, output


def test_current_repository_passes_and_reports_checked_packages():
    result = run_guard(ROOT)
    assert result.returncode == 0, result.stdout + result.stderr
    output = result.stdout.lower()
    assert "client" in output and "server" in output, output
    assert re.search(r"check|scan", output), output


@pytest.mark.parametrize("directory", ["lib", "test", "integration_test"])
@pytest.mark.parametrize("directive", ["import", "part"])
def test_client_sources_reject_relative_server_dependencies(tmp_path, directory, directive):
    path = f"packages/client/{directory}/consumer.dart"
    target = write(tmp_path, "packages/server/test/support/fixture.dart", "const value = 1;\n")
    uri = "../../server/test/support/fixture.dart"
    consumer = write(tmp_path, path, "// Package isolation applies before codegen.\n"
                     f"{directive} '{uri}';\n")
    # Two parents from client/{lib,test,integration_test} reach packages/.
    assert (consumer.parent / uri).resolve() == target.resolve()
    assert target.is_file()
    assert_rejected(run_guard(tmp_path), path, 2)


@pytest.mark.parametrize("directory", ["lib", "test", "integration_test"])
def test_client_sources_reject_server_package_imports(tmp_path, directory):
    path = f"packages/client/{directory}/consumer.dart"
    write(tmp_path, "packages/server/lib/domain/person.dart", "class Person {}\n")
    write(tmp_path, path, "import 'package:tentura_server/domain/person.dart';\n")
    assert_rejected(run_guard(tmp_path), path, 1)


def test_server_tests_accept_pure_dart_client_constants(tmp_path):
    write(tmp_path, "packages/client/test/support/contract.dart",
          "import 'dart:core';\nconst mutationName = 'personUntrust';\n")
    write(tmp_path, "packages/server/test/consumer_test.dart",
          "import '../../client/test/support/contract.dart';\n")
    result = run_guard(tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.strip(), "Successful checks must report what was checked"


@pytest.mark.parametrize("dependency", [
    "import 'package:collection/collection.dart';",
    "part 'contract.g.dart';",
])
def test_server_tests_reject_client_constants_with_package_or_part_dependencies(tmp_path, dependency):
    path = "packages/server/test/consumer_test.dart"
    write(tmp_path, "packages/client/test/support/contract.dart",
          f"{dependency}\nconst mutationName = 'personUntrust';\n")
    write(tmp_path, "packages/client/test/support/contract.g.dart", "part of 'contract.dart';\n")
    write(tmp_path, path, "// Server shards do not build Flutter or client parts.\n"
          "import '../../client/test/support/contract.dart';\n")
    assert_rejected(run_guard(tmp_path), path, 2)


def test_server_tests_reject_client_files_importing_flutter(tmp_path):
    path = "packages/server/test/consumer_test.dart"
    client_path = "packages/client/test/support/contract.dart"
    contract = write(tmp_path, client_path,
                     "import 'package:flutter/widgets.dart';\n"
                     "const mutationName = 'personUntrust';\n")
    consumer = write(tmp_path, path,
                     "// Server tests cannot load Flutter dependencies.\n"
                     "import '../../client/test/support/contract.dart';\n")
    assert (consumer.parent / "../../client/test/support/contract.dart").resolve() == contract.resolve()
    assert contract.is_file()
    result = run_guard(tmp_path)
    assert_rejected(result, path, 2)
    assert client_path in result.stdout + result.stderr


def test_server_tests_accept_client_constants_with_only_relative_dart_imports(tmp_path):
    path = "packages/server/test/consumer_test.dart"
    dependency = write(tmp_path, "packages/client/test/support/value.dart",
                       "const value = 'personUntrust';\n")
    contract = write(tmp_path, "packages/client/test/support/contract.dart",
                     "import 'value.dart';\nconst mutationName = value;\n")
    consumer = write(tmp_path, path,
                     "// No package imports or parts in the client support files.\n"
                     "import '../../client/test/support/contract.dart';\n")
    assert (contract.parent / "value.dart").resolve() == dependency.resolve()
    assert (consumer.parent / "../../client/test/support/contract.dart").resolve() == contract.resolve()
    assert dependency.is_file() and contract.is_file()
    result = run_guard(tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.strip(), "Successful checks must report what was checked"


def test_server_library_rejects_even_pure_dart_client_dependencies(tmp_path):
    path = "packages/server/lib/consumer.dart"
    write(tmp_path, "packages/client/lib/contract.dart", "const value = 1;\n")
    write(tmp_path, path, "import '../../client/lib/contract.dart';\n")
    assert_rejected(run_guard(tmp_path), path, 1)


def gate_fixture(tmp_path):
    """Other checks succeed; only the import guard returns a failure."""
    (tmp_path / "scripts").mkdir()
    shutil.copy2(ROOT / "scripts/run_tests.sh", tmp_path / "scripts/run_tests.sh")
    for script in ("check-analyze-baseline.sh", "check-custom-lints.sh"):
        write(tmp_path, f"scripts/{script}", "#!/bin/bash\nexit 0\n").chmod(0o755)
    write(tmp_path, "scripts/run_with_test_cleanup.sh",
          '#!/bin/bash\nwhile [[ "$1" != -- ]]; do shift; done\nshift\nexec "$@"\n').chmod(0o755)
    write(tmp_path, f"scripts/{GUARD}",
          "#!/usr/bin/env python3\nfrom pathlib import Path\nPath('guard-invoked').touch()\nraise SystemExit(23)\n").chmod(0o755)
    return tmp_path / "guard-invoked"


@pytest.mark.parametrize("profile", ["client-gates", "server-gates"])
def test_local_package_gates_propagate_import_guard_failure(tmp_path, profile):
    # Run the complete, unmodified entry point through its actual profile
    # dispatch; only external checks and the cleanup wrapper are stand-ins.
    marker = gate_fixture(tmp_path)
    result = subprocess.run(
        ["bash", str(tmp_path / "scripts/run_tests.sh"), profile],
        cwd=tmp_path, capture_output=True, text=True, timeout=30,
    )
    assert marker.exists(), f"{profile} skipped the import guard: {result.stderr}"
    assert result.returncode == 23, result.stdout + result.stderr


def test_ci_lints_step_propagates_import_guard_failure(tmp_path):
    source = (ROOT / ".github/workflows/pipeline.yml").read_text(encoding="utf-8")
    match = re.search(r'^\s*lints\)\s*\n(?P<body>.*?)^\s*;;', source, re.M | re.S)
    assert match, "Pipeline no longer exposes its lints shell branch"
    body = match.group("body")
    assert "check_repo_files_tags.py" in body, "Expected the repo-check step"
    (tmp_path / "packages/tentura_lints").mkdir(parents=True)
    # Execute the actual lints branch. Stand-ins prevent analyzer/test runs;
    # python invocations record only the new guard and return its failure.
    harness = '''set -euo pipefail
python3() {
  for arg in "$@"; do
    if [[ "${arg##*/}" == "$IMPORT_GUARD" ]]; then
      touch "$GUARD_MARKER"
      return 23
    fi
  done
}
dart() { return 0; }
bash() { return 0; }
'''
    marker = tmp_path / "guard-invoked"
    result = subprocess.run(
        ["bash", "-c", harness + body], cwd=tmp_path,
        env={**os.environ, "IMPORT_GUARD": GUARD, "GUARD_MARKER": str(marker)},
        capture_output=True, text=True, timeout=30,
    )
    assert marker.exists(), "CI's repo-check step skipped the import guard"
    assert result.returncode == 23, result.stdout + result.stderr
