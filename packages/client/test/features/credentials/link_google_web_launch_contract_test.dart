import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/platform_repository.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/credentials/data/repository/credentials_repository.dart';
import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/credentials/ui/bloc/credentials_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../auth/auth_test_helpers.dart';

// Launch contract (#1173 split): linkGoogleWeb launches the server-issued
// sign-in link through PlatformRepositoryPort.launchUri. A launcher failure
// surfaces as the typed UnknownPlatformException ("Unknown error") and is
// logged, instead of the raw plugin text; a malformed URL still surfaces the
// FormatException, as before.

const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

class _StartUrlCredentialsRepository extends Fake
    implements CredentialsRepository {
  _StartUrlCredentialsRepository(this.startUrl);

  final String startUrl;

  @override
  Future<List<CredentialEntity>> fetchCredentials() async => const [];

  @override
  Future<String> fetchGoogleLinkStartUrl() async => startUrl;
}

class _RecordingEffects implements UiEffectPort {
  final emitted = <UiEffect>[];

  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) => emitted.add(effect);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<LogRecord> records;
  late StreamSubscription<LogRecord> logSubscription;
  late List<MethodCall> launcherCalls;

  setUp(() {
    records = [];
    logSubscription = Logger.root.onRecord.listen(records.add);
    launcherCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
          launcherCalls.add(call);
          throw PlatformException(
            code: 'ACTIVITY_NOT_FOUND',
            message: 'raw plugin text',
          );
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, null);
    await logSubscription.cancel();
  });

  Future<({CredentialsCubit cubit, _RecordingEffects effects})> build(
    String startUrl,
  ) async {
    final effects = _RecordingEffects();
    final cubit = CredentialsCubit(
      CredentialsCase(
        _StartUrlCredentialsRepository(startUrl),
        EmptyAuthLocal(),
        env: const Env(),
        logger: Logger('test'),
      ),
      PlatformRepository(log: Logger('PlatformRepository')),
      effects,
    );
    addTearDown(cubit.close);
    // Let the constructor's fetch() settle.
    await pumpEventQueue();
    return (cubit: cubit, effects: effects);
  }

  test(
    'a launcher exception shows the typed Unknown error and is logged',
    () async {
      final (:cubit, :effects) = await build(
        'https://example.test/auth/google/link?state=abc',
      );

      await cubit.linkGoogleWeb();

      expect(launcherCalls, isNotEmpty, reason: 'the launcher was reached');
      final errors = effects.emitted.whereType<ShowError>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.error, isA<UnknownPlatformException>());
      expect(
        (errors.single.error as UnknownPlatformException).toEn,
        'Unknown error',
      );
      expect(errors.single.error.toString(), isNot(contains('raw plugin')));
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(
        records.where(
          (r) =>
              r.loggerName == 'PlatformRepository' &&
              r.level == Level.WARNING &&
              r.message.contains('Failed to launch URI') &&
              r.message.contains('raw plugin text'),
        ),
        hasLength(1),
      );
    },
  );

  test('a malformed start URL still surfaces FormatException', () async {
    final (:cubit, :effects) = await build('http://[::1');

    await cubit.linkGoogleWeb();

    expect(launcherCalls, isEmpty);
    final errors = effects.emitted.whereType<ShowError>().toList();
    expect(errors, hasLength(1));
    expect(errors.single.error, isA<FormatException>());
    expect(cubit.state.status, isA<StateIsSuccess>());
  });
}
