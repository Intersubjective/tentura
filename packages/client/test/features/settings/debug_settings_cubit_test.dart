import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/notification/domain/entity/fcm_test_send_result.dart';
import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_cubit.dart';
import 'package:tentura/features/settings/domain/entity/email_test_send_result.dart';
import 'package:tentura/features/settings/domain/port/email_test_remote_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/debug_settings_cubit.dart';
import 'package:tentura/features/settings/ui/message/debug_settings_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../notification/fcm_case_test.dart';

void main() {
  group('DebugSettingsCubit', () {
    late _FcmCaseSpy fcmCase;
    late FakeEmailTestRepository emailRepo;
    late FakeUiEffectPort effects;
    late DebugSettingsCubit cubit;

    setUp(() {
      fcmCase = _FcmCaseSpy();
      emailRepo = FakeEmailTestRepository();
      effects = FakeUiEffectPort();
      final authCase = buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote());
      cubit = DebugSettingsCubit(
        fcmCase,
        authCase,
        FcmCubit(fcmCase, authCase),
        emailRepo,
        effects,
      );
    });

    tearDown(() => cubit.close());

    test('successful FCM test starts cooldown', () async {
      await cubit.sendTestNotification();

      expect(cubit.state.isFcmTestEnabled, isFalse);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmTestSentMessage>()),
      );
    });

    test('failed FCM test does not start cooldown', () async {
      fcmCase.testResult = const FcmTestSendResult(
        ok: false,
        devices: 0,
        sent: 0,
        mock: false,
        reason: 'no_devices',
      );

      await cubit.sendTestNotification();

      expect(cubit.state.isFcmTestEnabled, isTrue);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugFcmTestNoDevicesMessage>()),
      );
    });

    test('successful email test starts cooldown', () async {
      await cubit.sendTestEmail();

      expect(cubit.state.isEmailTestEnabled, isFalse);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<DebugEmailTestSentMessage>()),
      );
    });
  });
}

class _FcmCaseSpy extends FcmCase {
  _FcmCaseSpy()
      : super(FakeFcmLocal(), FakeFcmRemote(), FakeSettings());

  FcmTestSendResult testResult = const FcmTestSendResult(
    ok: true,
    devices: 2,
    sent: 2,
    mock: false,
  );

  @override
  Future<FcmTestSendResult> sendTestNotification() async => testResult;
}

class FakeEmailTestRepository implements EmailTestRemoteRepositoryPort {
  EmailTestSendResult result = const EmailTestSendResult(ok: true, mock: false);

  @override
  Future<EmailTestSendResult> sendTestEmail() async => result;
}
