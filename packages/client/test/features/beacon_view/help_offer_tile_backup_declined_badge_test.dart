import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #708: a backup offer the author kept as standby showed a red "Declined"
// badge on the People tab when the same person had an earlier offer
// declined: the pair's last admission action stays `decline`, and the tile
// read it without checking whether the offer is still active.

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
    profile: Profile(id: 'auth', displayName: 'Author'),
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

TimelineHelpOffer _offer({
  required int offerKind,
  required bool isWithdrawn,
  HelpOfferAdmissionAction? admissionAction,
  String? lastDeclineReason,
}) {
  final t = DateTime.utc(2025);
  return TimelineHelpOffer(
    user: const Profile(id: 'helper', displayName: 'Helper Two'),
    message: 'I can step in',
    createdAt: t,
    updatedAt: t,
    isWithdrawn: isWithdrawn,
    admissionAction: admissionAction,
    lastDeclineReason: lastDeclineReason,
    offerKind: offerKind,
  );
}

Widget _authorTile(TimelineHelpOffer offer) => HelpOfferTile(
  helpOffer: offer,
  beaconId: 'B1',
  beaconAuthor: const Profile(id: 'auth', displayName: 'Author'),
  beaconAuthorId: 'auth',
  isAuthorView: true,
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

  testWidgets(
    'active backup offer after an earlier decline shows no Declined badge',
    (t) async {
      await t.pumpWidget(
        _wrap(
          _authorTile(
            _offer(
              offerKind: 1,
              isWithdrawn: false,
              admissionAction: HelpOfferAdmissionAction.decline,
              lastDeclineReason: 'Not this time',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Declined'), findsNothing);
      expect(find.text('Available as backup'), findsOneWidget);
    },
  );

  testWidgets(
    'active backup offer after an earlier decline shows no Declined badge (ru)',
    (t) async {
      await t.pumpWidget(
        _wrap(
          _authorTile(
            _offer(
              offerKind: 1,
              isWithdrawn: false,
              admissionAction: HelpOfferAdmissionAction.decline,
            ),
          ),
          locale: const Locale('ru'),
        ),
      );
      await t.pumpAndSettle();

      final ru = lookupL10n(const Locale('ru'));
      expect(find.text(ru.helpOfferStatusDeclined), findsNothing);
      expect(find.text(ru.helpOfferBackupBadge), findsOneWidget);
    },
  );

  testWidgets(
    'active ordinary re-offer after an earlier decline shows no Declined badge',
    (t) async {
      await t.pumpWidget(
        _wrap(
          _authorTile(
            _offer(
              offerKind: 0,
              isWithdrawn: false,
              admissionAction: HelpOfferAdmissionAction.decline,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Declined'), findsNothing);
    },
  );

  testWidgets('a declined offer still shows the Declined badge', (t) async {
    await t.pumpWidget(
      _wrap(
        _authorTile(
          _offer(
            offerKind: 0,
            isWithdrawn: true,
            admissionAction: HelpOfferAdmissionAction.decline,
            lastDeclineReason: 'Not this time',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Declined'), findsOneWidget);
  });
}
