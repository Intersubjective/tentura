import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/firebase_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/notification/data/service/fcm_service.dart';
import 'package:tentura/features/notification/domain/entity/notification_permission_status.dart';

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
      final service = FcmService.create(
        env: env,
        logger: logger,
        firebase: FirebaseService(
          env: env,
          logger: logger,
          isInitialized: true,
        ),
      );

      final permissions = await service.requestPermission();

      expect(permissions.authorized, isFalse);
      expect(
        records.where((r) => r.level >= Level.WARNING && r.error != null),
        isNotEmpty,
      );
    },
  );

  // #878: Firebase init that hung or failed at startup is skipped (#878
  // FirebaseService); push then runs on the fake service instead of calling
  // into a Firebase app that does not exist ([core/no-app] at FcmCubit start).
  test(
    'without an initialised Firebase app the fake service is used',
    () async {
      final service = FcmService.create(
        env: env,
        logger: Logger('FcmServiceTest'),
        firebase: FirebaseService(env: env, logger: Logger('FcmServiceTest')),
      );

      expect(() => service.onTokenRefresh, returnsNormally);
      expect(await service.getToken(), isNull);
      expect(
        await service.permissionStatus(),
        NotificationPermissionStatus.unsupported,
      );
    },
  );
}
