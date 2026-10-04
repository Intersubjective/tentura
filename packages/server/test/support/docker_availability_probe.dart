// Child-process entry point for `pg_required_mode_test.dart`: reports whether
// `IsolatedHasuraSession.isDockerAvailable()` returns or throws, so the test
// can run it with a PATH that has no `docker` binary.
import 'isolated_hasura_session.dart';

Future<void> main() async {
  try {
    final available = await IsolatedHasuraSession.isDockerAvailable();
    print('returned:$available');
  } on Object catch (e) {
    print('threw:$e');
  }
}
