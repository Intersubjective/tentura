import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #496 — the admission line on a helper card must come from the same
/// forward-trail data as the Forwards block (`isDirectAuthorForward`, i.e. an
/// active author -> helper forward edge), not from the admission event alone.
/// With no direct author forward the line says "Joined via the network".

const _directHintEn = 'You forwarded this request to them directly';
const _directHintRu = 'Вы переслали этот запрос напрямую';
const _networkHintEn = 'Joined via the network';
const _stewardDirectHintEn =
    'The author forwarded this request to them directly';
const _ownDirectHintEn = 'The author sent this request to you directly';
const _ownNetworkHintEn = 'You joined via the network';

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

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: locale,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

TimelineHelpOffer _admittedOffer({
  required String userId,
  required bool isDirectAuthorForward,
  HelpOfferAdmissionAction? admissionAction,
}) {
  final t = DateTime.utc(2025);
  return TimelineHelpOffer(
    user: Profile(id: userId, displayName: 'Helper'),
    message: 'I have a couch',
    createdAt: t,
    updatedAt: t,
    roomAccess: RoomAccessBits.admitted,
    admissionAction: admissionAction,
    isDirectAuthorForward: isDirectAuthorForward,
  );
}

Widget _authorTile(TimelineHelpOffer offer) => HelpOfferTile(
  helpOffer: offer,
  beaconId: 'B1',
  beaconAuthor: const Profile(id: 'me', displayName: 'Me'),
  beaconAuthorId: 'me',
  isAuthorView: true,
  viewerIsAuthor: true,
  showBackupHint: false,
);

/// A steward manages offers (author view) but is not the author.
Widget _stewardTile(TimelineHelpOffer offer) => HelpOfferTile(
  helpOffer: offer,
  beaconId: 'B1',
  beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
  beaconAuthorId: 'auth',
  isAuthorView: true,
  showBackupHint: false,
);

Widget _ownTile(TimelineHelpOffer offer) => HelpOfferTile(
  helpOffer: offer,
  beaconId: 'B1',
  beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
  beaconAuthorId: 'auth',
  isMine: true,
  showBackupHint: false,
);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(
      _FakePlatformRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('author view, admitted helper', () {
    testWidgets(
      'no admission event and no direct forward: says joined via the network',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            _authorTile(
              _admittedOffer(userId: 'h1', isDirectAuthorForward: false),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(_directHintEn), findsNothing);
        expect(find.text(_networkHintEn), findsOneWidget);
      },
    );

    testWidgets(
      'stale autoAdmit event without a live direct forward: '
      'says joined via the network',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            _authorTile(
              _admittedOffer(
                userId: 'h1',
                isDirectAuthorForward: false,
                admissionAction: HelpOfferAdmissionAction.autoAdmit,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(_directHintEn), findsNothing);
        expect(find.text(_networkHintEn), findsOneWidget);
      },
    );

    testWidgets('a live direct author forward keeps the forwarded line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _authorTile(
            _admittedOffer(
              userId: 'h1',
              isDirectAuthorForward: true,
              admissionAction: HelpOfferAdmissionAction.autoAdmit,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_directHintEn), findsOneWidget);
      expect(find.text(_networkHintEn), findsNothing);
    });

    testWidgets('Russian: no direct-forward claim without a direct forward', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _authorTile(
            _admittedOffer(userId: 'h1', isDirectAuthorForward: false),
          ),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_directHintRu), findsNothing);
      // A real translation, not the English fallback.
      expect(find.text(_networkHintEn), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HelpOfferTile),
          matching: find.textContaining('сет'),
        ),
        findsOneWidget,
      );
    });
  });

  group('helper own card, admitted automatically', () {
    testWidgets(
      'autoAdmit without a direct forward: says joined via the network',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            _ownTile(
              _admittedOffer(
                userId: 'me',
                isDirectAuthorForward: false,
                admissionAction: HelpOfferAdmissionAction.autoAdmit,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(_directHintEn), findsNothing);
        expect(find.text(_ownDirectHintEn), findsNothing);
        expect(find.text(_ownNetworkHintEn), findsOneWidget);
      },
    );

    // The helper did not forward anything: the author's line is not theirs.
    testWidgets('a direct author forward is told to the helper as such', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _ownTile(
            _admittedOffer(
              userId: 'me',
              isDirectAuthorForward: true,
              admissionAction: HelpOfferAdmissionAction.autoAdmit,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_directHintEn), findsNothing);
      expect(find.text(_ownDirectHintEn), findsOneWidget);
    });
  });

  group('steward view, admitted helper', () {
    testWidgets("a steward's own offer reads as their own card", (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HelpOfferTile(
            helpOffer: _admittedOffer(
              userId: 'me',
              isDirectAuthorForward: true,
              admissionAction: HelpOfferAdmissionAction.autoAdmit,
            ),
            beaconId: 'B1',
            beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
            beaconAuthorId: 'auth',
            isAuthorView: true,
            isMine: true,
            showBackupHint: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_stewardDirectHintEn), findsNothing);
      expect(find.text(_ownDirectHintEn), findsOneWidget);
    });

    testWidgets('a direct author forward names the author, not "you"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _stewardTile(
            _admittedOffer(
              userId: 'h1',
              isDirectAuthorForward: true,
              admissionAction: HelpOfferAdmissionAction.autoAdmit,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_directHintEn), findsNothing);
      expect(find.text(_stewardDirectHintEn), findsOneWidget);
      expect(find.text('Forwarded by you'), findsNothing);
    });

    testWidgets('no direct forward: joined via the network', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _stewardTile(
            _admittedOffer(userId: 'h1', isDirectAuthorForward: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_stewardDirectHintEn), findsNothing);
      expect(find.text(_networkHintEn), findsOneWidget);
    });
  });
}
