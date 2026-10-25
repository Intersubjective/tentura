import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/credentials/data/repository/credentials_repository.dart';
import 'package:tentura/features/credentials/data/service/device_label_parser.dart';
import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';
import 'package:tentura/features/credentials/domain/entity/credential_types.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/credentials/ui/bloc/credentials_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';

// #467: two device keys made in different browsers showed as two identical
// "Recovery seed · <key>… · <age>" rows; nothing said which device or browser
// each came from. The client now sends a device label when it links a key
// ("Chrome on Linux"), the server keeps it, and the row shows it.

class _ListCredentialsRepository extends Fake implements CredentialsRepository {
  _ListCredentialsRepository(this.credentials);

  final List<CredentialEntity> credentials;

  @override
  Future<List<CredentialEntity>> fetchCredentials() async =>
      List.of(credentials);
}

class _NoopEffects implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}

class _UnusedPlatform extends Fake implements PlatformRepositoryPort {}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: CredentialsRoute.page, initial: true),
  ];
}

Future<void> _pumpScreen(
  WidgetTester tester,
  List<CredentialEntity> credentials,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final case_ = CredentialsCase(
    _ListCredentialsRepository(credentials),
    EmptyAuthLocal(),
    env: const Env(),
    logger: Logger('test'),
  );
  GetIt.I.registerFactory<CredentialsCubit>(
    () => CredentialsCubit(case_, _UnusedPlatform(), _NoopEffects()),
  );
  addTearDown(GetIt.I.reset);

  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) =>
          TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
      routerConfig: router.config(),
    ),
  );
  await tester.pumpAndSettle();
}

const _chromeUa =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

void main() {
  group('deviceLabelFromUserAgent', () {
    test('names the browser and the OS', () {
      expect(deviceLabelFromUserAgent(_chromeUa), 'Chrome on Linux');
      expect(
        deviceLabelFromUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) '
          'Gecko/20100101 Firefox/131.0',
        ),
        'Firefox on Windows',
      );
      expect(
        deviceLabelFromUserAgent(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
          'Mobile/15E148 Safari/604.1',
        ),
        'Safari on iOS',
      );
      expect(
        deviceLabelFromUserAgent(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 '
          'Safari/537.36 Edg/130.0.0.0',
        ),
        'Edge on macOS',
      );
      expect(
        deviceLabelFromUserAgent(
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
        ),
        'Chrome on Android',
      );
    });

    test('returns null for an agent it cannot read', () {
      expect(deviceLabelFromUserAgent(''), isNull);
      expect(deviceLabelFromUserAgent('curl/8.0'), isNull);
    });
  });

  test('the link body carries the device label when there is one', () {
    expect(CredentialsRepository.linkSeedBody('tok', 'Chrome on Linux'), {
      'authRequestToken': 'tok',
      'deviceLabel': 'Chrome on Linux',
    });
    expect(CredentialsRepository.linkSeedBody('tok', null), {
      'authRequestToken': 'tok',
    });
    expect(CredentialsRepository.linkSeedBody('tok', '  '), {
      'authRequestToken': 'tok',
    });
  });

  test('CredentialEntity.fromMap reads the device label', () {
    final c = CredentialEntity.fromMap(const {
      'id': 'c1',
      'type': 'ed25519_device',
      'identifier': 'PUBKEY',
      'deviceLabel': 'Chrome on Linux',
    });
    expect(c.deviceLabel, 'Chrome on Linux');

    final none = CredentialEntity.fromMap(const {
      'id': 'c2',
      'type': 'ed25519_device',
      'identifier': 'PUBKEY',
      'deviceLabel': null,
    });
    expect(none.deviceLabel, isNull);
  });

  testWidgets('a device key row names the device it was added on', (
    tester,
  ) async {
    await _pumpScreen(tester, const [
      CredentialEntity(
        id: 'seed-1',
        type: CredentialTypes.ed25519Device,
        identifier: 'AAAAAAAAAAAAAAAAAAAA',
        deviceLabel: 'Chrome on Linux',
      ),
      CredentialEntity(
        id: 'seed-2',
        type: CredentialTypes.ed25519Device,
        identifier: 'BBBBBBBBBBBBBBBBBBBB',
        deviceLabel: 'Safari on iOS',
      ),
    ]);

    expect(
      find.text('Chrome on Linux · AAAAAAAAAAAAAAAA…'),
      findsOneWidget,
    );
    expect(find.text('Safari on iOS · BBBBBBBBBBBBBBBB…'), findsOneWidget);
  });

  testWidgets('the label comes before the age on a dated row', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      CredentialEntity(
        id: 'seed-1',
        type: CredentialTypes.ed25519Device,
        identifier: 'AAAAAAAAAAAAAAAAAAAA',
        deviceLabel: 'Chrome on Linux',
        createdAt: DateTime(2026, 1, 14, 12),
      ),
    ]);

    expect(
      find.textContaining(
        RegExp(r'^Chrome on Linux · AAAAAAAAAAAAAAAA… · \S'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a row without a label reads as before', (tester) async {
    await _pumpScreen(tester, const [
      CredentialEntity(
        id: 'seed-1',
        type: CredentialTypes.ed25519Device,
        identifier: 'AAAAAAAAAAAAAAAAAAAA',
      ),
    ]);

    expect(find.text('AAAAAAAAAAAAAAAA…'), findsOneWidget);
  });
}
