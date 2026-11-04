import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile/ui/widget/profile_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  _TestProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// Long enough to exceed three lines at 375 px with [TextTheme.bodyMedium].
final _longDescription = List.filled(80, 'Описание профиля').join(' ');

Finder _profileDescriptionText() => find.descendant(
  of: find.byType(ShowMoreText),
  matching: find.byWidgetPredicate(
    (w) => w is Text && w.textSpan != null,
  ),
);

void _tapShowMoreLink(WidgetTester tester, String label) {
  TapGestureRecognizer? recognizer;
  tester.widget<Text>(_profileDescriptionText()).textSpan!.visitChildren((
    span,
  ) {
    if (span is TextSpan &&
        span.text == label &&
        span.recognizer is TapGestureRecognizer) {
      recognizer = span.recognizer! as TapGestureRecognizer;
      return false;
    }
    return true;
  });
  expect(recognizer, isNotNull, reason: 'no "$label" link');
  recognizer!.onTap!();
}

void main() {
  late _FakePlatformRepository platform;

  setUp(() async {
    await GetIt.I.reset();
    platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets(
    '375×667 RU: profile body bio trim links come from wire-fetched profile',
    (tester) async {
      await usePhoneSurface(tester);
      const id = 'Ubio0000000001';
      late Profile profile;
      final sent = <WireSent>[];

      await withRemoteWire(
        {
          'UserFetchById': {
            '__typename': 'query_root',
            'user_by_pk': {
              '__typename': 'user',
              'id': id,
              'created_at': '2026-01-01T00:00:00Z',
              'display_name': 'Мария',
              'handle': 'maria',
              'description': _longDescription,
              'my_vote': 0,
              'trusts_viewer': false,
              'is_mutual_friend': false,
              'image': null,
              'scores': <Object>[],
              'user_presence': null,
              'user_availability': null,
            },
          },
        },
        sent,
        (remote) async {
          profile = await ProfileRepository(remote).fetchById(id);
        },
      );

      expect(sent.single.operationName, 'UserFetchById');
      expect(profile.description, _longDescription);

      final l10nRu = lookupL10n(const Locale('ru'));
      final profileCubit = _TestProfileCubit(profile);

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
              ],
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    ProfileBody(
                      profile: profile,
                      profileCubit: profileCubit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ShowMoreText), findsOneWidget);
      expect(find.text('read more'), findsNothing);
      expect(
        find.textContaining(l10nRu.beaconShowcaseReadMore),
        findsOneWidget,
      );

      _tapShowMoreLink(tester, l10nRu.beaconShowcaseReadMore);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(l10nRu.beaconShowcaseShowLess),
        findsOneWidget,
      );
    },
  );
}
