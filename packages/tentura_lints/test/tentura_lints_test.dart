import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:tentura_lints/src/rules/cubit_requires_use_case_for_multi_repos.dart';
import 'package:tentura_lints/src/rules/no_cubit_to_data_service_imports.dart';
import 'package:tentura_lints/src/rules/no_domain_to_data_imports.dart';
import 'package:tentura_lints/src/rules/no_raw_graphql_in_dart.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

@reflectiveTest
class NoDomainToDataImportsTest extends AnalysisRuleTest {
  @override
  String get testFileName => 'domain/entity.dart';

  @override
  void setUp() {
    rule = NoDomainToDataImports();
    super.setUp();
  }

  Future<void> test_reports_data_import() async {
    await assertDiagnostics(
      '''
import 'package:tentura/data/repository/foo_repository.dart';
''',
      [
        lint(0, 61),
        error(diag.uriDoesNotExist, 7, 53),
      ],
    );
  }

  Future<void> test_allows_domain_import() async {
    await assertDiagnostics(
      '''
import 'package:tentura/domain/entity/foo.dart';
''',
      [error(diag.uriDoesNotExist, 7, 40)],
    );
  }
}

@reflectiveTest
class NoCubitToDataServiceImportsTest extends AnalysisRuleTest {
  @override
  String get testFileName => 'ui/bloc/sample_cubit.dart';

  @override
  void setUp() {
    rule = NoCubitToDataServiceImports();
    super.setUp();
  }

  Future<void> test_reports_data_service_import() async {
    await assertDiagnostics(
      '''
import 'package:tentura/data/service/remote_api_client.dart';
''',
      [
        lint(0, 61),
        error(diag.uriDoesNotExist, 7, 53),
      ],
    );
  }

  Future<void> test_allows_repository_import() async {
    await assertDiagnostics(
      '''
import 'package:tentura/data/repository/foo_repository.dart';
''',
      [error(diag.uriDoesNotExist, 7, 53)],
    );
  }
}

@reflectiveTest
class CubitRequiresUseCaseForMultiReposTest extends AnalysisRuleTest {
  @override
  String get testFileName =>
      'packages/client/lib/features/foo/ui/bloc/foo_cubit.dart';

  @override
  void setUp() {
    rule = CubitRequiresUseCaseForMultiRepos();

    newPackage('bloc').addFile(
      'lib/bloc.dart',
      'class Cubit<T> {\n  Cubit(T state);\n}\n',
    );

    final tentura = newPackage('tentura');
    tentura.addFile(
      'lib/data/repository/foo_repository.dart',
      'class FooRepository {}\n',
    );
    tentura.addFile(
      'lib/data/repository/bar_repository.dart',
      'class BarRepository {}\n',
    );
    tentura.addFile(
      'lib/domain/use_case/foo_case.dart',
      'class FooCase {}\n',
    );

    super.setUp();
  }

  Future<void> test_reports_multi_repo_without_case() async {
    await assertDiagnostics(
      '''
import 'package:bloc/bloc.dart';
import 'package:tentura/data/repository/foo_repository.dart';
import 'package:tentura/data/repository/bar_repository.dart';

class FooCubit extends Cubit<int> {
  FooCubit(this._foo, this._bar) : super(0);

  final FooRepository _foo;
  final BarRepository _bar;
}
''',
      [lint(196, 42)],
    );
  }

  Future<void> test_allows_multi_repo_with_case() async {
    await assertDiagnostics(
      '''
import 'package:bloc/bloc.dart';
import 'package:tentura/data/repository/foo_repository.dart';
import 'package:tentura/data/repository/bar_repository.dart';
import 'package:tentura/domain/use_case/foo_case.dart';

class FooCubit extends Cubit<int> {
  FooCubit(this._foo, this._bar, this._case) : super(0);

  final FooRepository _foo;
  final BarRepository _bar;
  final FooCase _case;
}
''',
      const [],
    );
  }
}

@reflectiveTest
class NoRawGraphqlInDartTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoRawGraphqlInDart();
    super.setUp();
  }

  Future<void> test_reports_gql_call() async {
    await assertDiagnostics(
      "import 'package:gql/gql.dart';\n"
      'void main() {\n'
      "  gql('query Foo { id }');\n"
      '}\n',
      [
        error(diag.uriDoesNotExist, 7, 22),
        error(diag.undefinedFunction, 47, 3),
        lint(51, 18),
      ],
    );
  }

  Future<void> test_allows_regular_string() async {
    await assertNoDiagnostics(
      '''
const title = 'hello world';
''',
    );
  }
}

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoDomainToDataImportsTest);
    defineReflectiveTests(NoCubitToDataServiceImportsTest);
    defineReflectiveTests(CubitRequiresUseCaseForMultiReposTest);
    defineReflectiveTests(NoRawGraphqlInDartTest);
  });
}
