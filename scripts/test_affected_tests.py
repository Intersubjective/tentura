"""Import-graph test selection (scripts/affected_tests.py): a test is selected
exactly when a changed file reaches it through imports, and every input the
graph cannot see follows the rule its docstring states. Runs in the lints
shard, on a small synthetic workspace plus one pass over the real tree."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from affected_tests import Graph, select

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "affected_tests.py"

CLIENT = "packages/client"
SERVER = "packages/server"

ARB = {"@@locale": "en", "greeting": "Hi", "farewell": "Bye", "@farewell": {}}

# A small workspace: client lib a <- b <- c with tests on each; l10n users,
# an ARB reader, GraphQL documents around a serializers hub, a fixture, a
# repo-files test, source readers, hook/ and web/ files; a server pg test and
# a migration.
FILES = {
    f"{CLIENT}/lib/a.dart": "class A {}\n",
    f"{CLIENT}/lib/b.dart": "import 'package:tentura/a.dart';\n",
    f"{CLIENT}/lib/c.dart": "export 'b.dart';\n",
    f"{CLIENT}/lib/web.dart": "import 'stub.dart' if (dart.library.js_interop) 'js.dart';\n",
    f"{CLIENT}/lib/js.dart": "",
    f"{CLIENT}/lib/stub.dart": "",
    # l10n: the generated L10n is imported by both widgets; each names a key.
    f"{CLIENT}/lib/ui/l10n/l10n.dart": "abstract class L10n { String get greeting; String get farewell; }\n",
    f"{CLIENT}/lib/hello.dart": "import 'ui/l10n/l10n.dart';\nString f(L10n l) => l.greeting;\n",
    f"{CLIENT}/lib/bye.dart": "import 'ui/l10n/l10n.dart';\nString f(L10n l) => l.farewell;\n",
    f"{CLIENT}/l10n/app_en.arb": json.dumps(ARB),
    f"{CLIENT}/test/hello_test.dart": "import 'package:tentura/hello.dart';\n",
    f"{CLIENT}/test/bye_test.dart": "import 'package:tentura/bye.dart';\n",
    f"{CLIENT}/test/support/arb_keys.dart": "final arb = File('l10n/app_en.arb');\n",
    f"{CLIENT}/test/arb_contract_test.dart": "import 'support/arb_keys.dart';\n",
    f"{CLIENT}/test/fake_l10n_test.dart": "class _L extends L10n {}\n",
    # GraphQL: two documents, their generated files and the serializers hub.
    f"{CLIENT}/lib/feat/q.graphql": "query Q { x }\n",
    f"{CLIENT}/lib/feat/_g/q.req.gql.dart": "import '../../data/gql/_g/serializers.gql.dart';\n",
    f"{CLIENT}/lib/feat/repo.dart": "import '_g/q.req.gql.dart';\n",
    f"{CLIENT}/lib/other/r.graphql": "query R { y }\n",
    f"{CLIENT}/lib/other/_g/r.req.gql.dart": "import '../../data/gql/_g/serializers.gql.dart';\n",
    f"{CLIENT}/lib/other/repo2.dart": "import '_g/r.req.gql.dart';\n",
    f"{CLIENT}/lib/data/gql/_g/serializers.gql.dart": (
        "import '../custom_serializer.dart';\n"
        "import '../../../feat/_g/q.req.gql.dart';\n"
        "import '../../../other/_g/r.req.gql.dart';\n"
    ),
    f"{CLIENT}/lib/data/gql/custom_serializer.dart": "",
    f"{CLIENT}/lib/data/gql/client.dart": "import '_g/serializers.gql.dart';\n",
    f"{CLIENT}/test/repo_test.dart": "import 'package:tentura/feat/repo.dart';\n",
    f"{CLIENT}/test/repo2_test.dart": "import 'package:tentura/other/repo2.dart';\n",
    f"{CLIENT}/test/gql_client_test.dart": "import 'package:tentura/data/gql/client.dart';\n",
    # Plain graph cases.
    f"{CLIENT}/test/a_test.dart": "import 'package:tentura/a.dart';\n",
    f"{CLIENT}/test/c_test.dart": "import 'package:tentura/c.dart';\n",
    f"{CLIENT}/test/js_test.dart": "import 'package:tentura/web.dart';\n",
    f"{CLIENT}/test/fixture_test.dart": "final f = 'data/sample.json';\n",
    f"{CLIENT}/test/data/sample.json": "{}\n",
    f"{CLIENT}/test/docs_test.dart": "@Tags(['repo-files'])\nlibrary;\n",
    f"{CLIENT}/test/helper.dart": "import 'package:tentura/a.dart';\n",
    f"{CLIENT}/test/via_helper_test.dart": "import 'helper.dart';\n",
    f"{CLIENT}/test/root_test.dart": "import 'package:tentura_root/shared.dart';\n",
    "lib/shared.dart": "",
    # Source readers: one by place (no path: every change), one reading all
    # of lib/, one reading lib/feat/ only; a dart:io read of a fixture alone
    # is not one.
    f"{CLIENT}/test/architecture/layering_test.dart": "void main() {}\n",
    f"{CLIENT}/test/scan_test.dart": (
        "import 'dart:io';\nfinal files = Directory('lib').listSync();\n"
    ),
    f"{CLIENT}/test/feat_scan_test.dart": (
        "import 'dart:io';\nfinal d = Directory('${root}/lib/feat/$name');\n"
    ),
    f"{CLIENT}/test/fixture_io_test.dart": "import 'dart:io';\nfinal f = File('data/x.json');\n",
    # GraphQL schema and a test reading a document by name.
    f"{CLIENT}/lib/data/gql/schema.graphql": "type Query { x: Int }\n",
    f"{CLIENT}/test/q_doc_test.dart": "final doc = 'q.graphql';\n",
    f"{CLIENT}/test/schema_doc_test.dart": "final doc = 'schema.graphql';\n",
    # hook/ is source too; web/ files are read by what names them.
    f"{CLIENT}/hook/build/version.dart": "import 'manifest_name.dart';\n",
    f"{CLIENT}/hook/build/manifest_name.dart": "const name = 'manifest.json';\n",
    f"{CLIENT}/test/hook/version_test.dart": "import '../../hook/build/version.dart';\n",
    f"{CLIENT}/web/manifest.json": "{}\n",
    f"{CLIENT}/web/index.html": "<html></html>\n",
    f"{SERVER}/lib/data/database/migration/m0001.dart": "",
    f"{SERVER}/lib/s.dart": "",
    f"{SERVER}/test/s_test.dart": "import 'package:tentura_server/s.dart';\n",
    f"{SERVER}/test/pg_test.dart": "@Tags(['pg'])\nlibrary;\n",
}

L10N_ALWAYS = ["arb_contract_test.dart", "fake_l10n_test.dart"]
# Selected with every Dart change under the client's lib/ (layering_test with
# every Dart change of the client).
READERS = ["layering_test.dart", "scan_test.dart"]


def with_readers(*names):
    return sorted([*names, *READERS])


def absent(_path: str):
    return None


class SyntheticTreeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        for path, text in FILES.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(text)
        cls.graph = Graph(root)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def sel(self, *changed, pkg=CLIENT, before=absent, after=absent):
        return select(self.graph, pkg, list(changed), before, after)

    def arb(self, new: dict, old: dict = ARB):
        path = f"{CLIENT}/l10n/app_en.arb"
        return self.sel(
            path,
            before=lambda _p: json.dumps(old),
            after=lambda _p: json.dumps(new),
        )

    def names(self, sel):
        return sorted(Path(t).name for t in sel.tests)

    def assert_whole(self, sel, pkg=CLIENT):
        self.assertTrue(sel.fallbacks)
        self.assertEqual(sel.tests, self.graph.tests(pkg))

    def test_transitive_imports_and_exports(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/lib/a.dart")),
            with_readers("a_test.dart", "c_test.dart", "via_helper_test.dart"),
        )

    def test_unimported_change_selects_only_source_readers(self):
        sel = self.sel(f"{CLIENT}/lib/orphan.dart")
        self.assertEqual((self.names(sel), sel.fallbacks), (READERS, []))

    def test_source_readers_found_by_place_and_by_dart_io_reads(self):
        self.assertEqual(
            sorted(Path(f).name for f in self.graph.source_readers(CLIENT)),
            sorted(["feat_scan_test.dart", *READERS]),
        )
        self.assertEqual(self.graph.source_readers(SERVER), frozenset())
        self.assertEqual(
            {Path(f).name: v for f, v in self.graph.reader_prefixes(CLIENT).items()},
            {"layering_test.dart": (), "scan_test.dart": ("lib",), "feat_scan_test.dart": ("lib/feat",)},
        )

    def test_source_reader_scoped_to_the_path_it_names(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/lib/feat/repo.dart")),
            with_readers("feat_scan_test.dart", "repo_test.dart"),
        )
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/test/helper.dart")),
            ["layering_test.dart", "via_helper_test.dart"],
        )

    def test_source_readers_not_selected_by_outside_or_non_source_changes(self):
        self.assertEqual(self.names(self.sel("lib/shared.dart")), ["docs_test.dart", "root_test.dart"])
        self.assertEqual(self.names(self.sel(f"{CLIENT}/test/data/sample.json")), ["fixture_test.dart"])

    def test_conditional_import_both_branches(self):
        for f in ("js.dart", "stub.dart"):
            self.assertEqual(self.names(self.sel(f"{CLIENT}/lib/{f}")), with_readers("js_test.dart"))

    def test_changed_test_selects_itself(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/test/a_test.dart")),
            ["a_test.dart", "layering_test.dart"],
        )

    def test_hook_dart_is_in_the_graph(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/hook/build/manifest_name.dart")),
            ["layering_test.dart", "version_test.dart"],
        )

    def test_generated_l10n_dart_change_reaches_every_user(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/lib/ui/l10n/l10n.dart")),
            with_readers("bye_test.dart", "hello_test.dart"),
        )

    def test_root_package_dart_reaches_client_and_adds_repo_files(self):
        self.assertEqual(
            self.names(self.sel("lib/shared.dart")), ["docs_test.dart", "root_test.dart"]
        )

    def test_arb_text_change_selects_the_key_users_and_arb_readers(self):
        self.assertEqual(
            self.names(self.arb({**ARB, "greeting": "Hello"})),
            sorted(["hello_test.dart", *L10N_ALWAYS]),
        )

    def test_arb_metadata_change_selects_the_key_users(self):
        self.assertEqual(
            self.names(self.arb({**ARB, "@farewell": {"description": "x"}})),
            sorted(["bye_test.dart", *L10N_ALWAYS]),
        )

    def test_arb_removed_key_selects_its_users(self):
        new = {k: v for k, v in ARB.items() if k != "greeting"}
        self.assertEqual(
            self.names(self.arb(new)), sorted(["hello_test.dart", *L10N_ALWAYS])
        )

    def test_arb_new_key_selects_only_arb_readers(self):
        self.assertEqual(self.names(self.arb({**ARB, "newKey": "New"})), L10N_ALWAYS)

    def test_arb_that_cannot_be_compared_selects_whole_package(self):
        path = f"{CLIENT}/l10n/app_en.arb"
        cases = {
            "invalid JSON": (lambda _p: json.dumps(ARB), lambda _p: "{"),
            "new locale": (absent, lambda _p: json.dumps(ARB)),
            "removed locale": (lambda _p: json.dumps(ARB), absent),
            "@@locale": (lambda _p: json.dumps(ARB), lambda _p: json.dumps({**ARB, "@@locale": "de"})),
        }
        for case, (before, after) in cases.items():
            with self.subTest(case=case):
                self.assert_whole(self.sel(path, before=before, after=after))

    def test_graphql_selects_its_document_users_not_through_serializers(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/lib/feat/q.graphql")),
            with_readers("feat_scan_test.dart", "q_doc_test.dart", "repo_test.dart"),
        )

    def test_graphql_schema_selects_every_generated_file_user_and_its_readers(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/lib/data/gql/schema.graphql")),
            with_readers(
                "gql_client_test.dart", "repo2_test.dart", "repo_test.dart",
                "schema_doc_test.dart",
            ),
        )

    def test_dart_change_under_serializers_still_goes_through_them(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/lib/data/gql/custom_serializer.dart")),
            with_readers("gql_client_test.dart", "repo2_test.dart", "repo_test.dart"),
        )

    def test_graphql_without_generated_files_selects_whole_package(self):
        self.assert_whole(self.sel(f"{CLIENT}/lib/feat/new.graphql"))

    def test_fixture_selects_the_tests_naming_it(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/test/data/sample.json")), ["fixture_test.dart"]
        )

    def test_unnamed_fixture_selects_whole_package(self):
        self.assert_whole(self.sel(f"{CLIENT}/test/data/orphan.json"))

    def test_test_config_selects_whole_package(self):
        for rel in (
            "test/flutter_test_config.dart",
            "dart_test.yaml",
            "build.yaml",
            "l10n.yaml",
            "analysis_options.yaml",
            "env/test.env",
        ):
            with self.subTest(rel=rel):
                self.assert_whole(self.sel(f"{CLIENT}/{rel}"))

    def test_other_non_dart_under_lib_or_assets_selects_whole_package(self):
        for rel in ("lib/data.json", "assets/x.svg", "integration_test/run.sh"):
            with self.subTest(rel=rel):
                self.assert_whole(self.sel(f"{CLIENT}/{rel}"))

    def test_pubspec_version_bump_alone_selects_nothing(self):
        sel = self.sel(
            f"{CLIENT}/pubspec.yaml",
            before=lambda _p: "name: tentura\nversion: 1.0.0+1\n",
            after=lambda _p: "name: tentura\nversion: 1.0.1+2\n",
        )
        self.assertEqual((sel.tests, sel.fallbacks), (set(), []))

    def test_pubspec_dependency_change_selects_whole_package(self):
        before = lambda _p: "dependencies:\n  intl: 0.19.0\n"  # noqa: E731
        after = lambda _p: "dependencies:\n  intl: 0.20.0\n"  # noqa: E731
        for path in (f"{CLIENT}/pubspec.yaml", "pubspec.yaml"):
            with self.subTest(path=path):
                self.assert_whole(self.sel(path, before=before, after=after))
        self.assert_whole(self.sel("pubspec.lock"))

    def test_outside_change_adds_repo_files_tests(self):
        self.assertEqual(self.names(self.sel("docs/x.md")), ["docs_test.dart"])
        self.assertEqual(self.names(self.sel(f"{SERVER}/lib/s.dart")), ["docs_test.dart"])

    def test_web_file_selects_what_names_it(self):
        self.assertEqual(
            self.names(self.sel(f"{CLIENT}/web/manifest.json")), ["version_test.dart"]
        )

    def test_unnamed_web_file_selects_whole_package(self):
        self.assert_whole(self.sel(f"{CLIENT}/web/index.html"))

    def test_other_unnamed_file_of_the_package_selects_nothing(self):
        sel = self.sel(f"{CLIENT}/README.md", f"{CLIENT}/android/app/x.xml")
        self.assertEqual((sel.tests, sel.fallbacks), (set(), []))

    def test_server_migration_adds_pg_tests(self):
        sel = self.sel(f"{SERVER}/lib/data/database/migration/m0001.dart", pkg=SERVER)
        self.assertEqual(self.names(sel), ["pg_test.dart"])
        self.assertEqual(self.names(self.sel(f"{SERVER}/lib/s.dart", pkg=SERVER)), ["s_test.dart"])


class RealTreeTest(unittest.TestCase):
    def test_cli_runs_on_the_real_tree(self):
        out = subprocess.run(
            [sys.executable, str(SCRIPT), CLIENT],
            cwd=REPO,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        for line in out.splitlines():
            self.assertTrue(line.startswith("test/") and line.endswith("_test.dart"), line)
            self.assertTrue((REPO / CLIENT / line).is_file(), line)

    def test_real_graph_sees_the_test_trees_and_the_hubs(self):
        graph = Graph(REPO)
        self.assertGreater(len(graph.tests(CLIENT)), 500)
        self.assertGreater(len(graph.tests(SERVER)), 200)
        # The hub the GraphQL rule steps around is where the rule expects it.
        hub = f"{CLIENT}/lib/data/gql/_g/serializers.gql.dart"
        if (REPO / hub).is_file():
            self.assertGreater(len(graph.importers[hub]), 100)
        # The generated L10n the ARB rule maps keys to (git-ignored: the CI
        # lints shard runs no codegen).
        l10n = f"{CLIENT}/lib/ui/l10n/l10n.dart"
        if (REPO / l10n).is_file():
            self.assertIn(l10n, graph.files)
        # hook/ is walked; source readers are found without a list.
        self.assertIn(f"{CLIENT}/hook/build/web_build_version.dart", graph.files)
        readers = graph.source_readers(CLIENT)
        for name in ("home_tab_spec_test.dart", "verify_web_version_consistency_test.dart"):
            self.assertTrue(any(f.endswith("/" + name) for f in readers), name)
        self.assertTrue(
            any(f.endswith("/scoped_main_db_access_test.dart") for f in graph.source_readers(SERVER))
        )


if __name__ == "__main__":
    unittest.main()
