import 'package:test/test.dart';

import 'package:tentura_server/app/app.dart';

void main() {
  test('runWithTestEnv completes with the error of a worker that fails '
      'before it is ready', () async {
    await expectLater(
      App()
          .runWithTestEnv(worker: (_) async => throw StateError('boom'))
          .timeout(const Duration(seconds: 10)),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'boom'),
      ),
    );
  });
}
