import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/notification/data/service/fcm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A config valid enough for the real (non-fake) service.
  const env = Env(
    firebaseApiKey: 'AIzaSyExampleKey',
    firebaseAppId: '1:123456789:web:abcdef123456',
    firebaseProjectId: 'tentura-dev',
    firebaseMessagingSenderId: '123456789',
  );

  // #607 (from #469): only the unsupported-browser error was turned into
  // "denied"; any other Firebase error escaped to the caller (the cubit's
  // account-change sync, Settings → Debug), so a permission hiccup crashed
  // that flow instead of reading as "not authorized".
  test(
    'requestPermission reports "not authorized" instead of throwing on a '
    'Firebase error other than unsupported-browser',
    () async {
      final logger = Logger('FcmServiceTest');
      final records = <LogRecord>[];
      final sub = logger.onRecord.listen(records.add);
      addTearDown(sub.cancel);

      // No Firebase app is initialised in tests, so the plugin throws
      // FirebaseException [core/no-app] — a non-"unsupported" error.
      final service = FcmService.create(env: env, logger: logger);

      final permissions = await service.requestPermission();

      expect(permissions.authorized, isFalse);
      expect(
        records.where((r) => r.level >= Level.WARNING && r.error != null),
        isNotEmpty,
      );
    },
  );
}
