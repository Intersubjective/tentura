// An offer opened from My Work must always offer a way to close the card,
// whatever state the offer is in. The action is addressed by the key
// `help-offer-close-card:<offererId>`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/sheet/help_offer_tile_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/help_offer_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _author = Profile(id: 'author-1', displayName: 'Author');
const _offerer = Profile(id: 'offerer-1', displayName: 'Offerer');

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.viewer);

  final Profile viewer;

  @override
  ProfileState get state => ProfileState(profile: viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

FakeHelpOfferCoordinationRow _row({
  int offerKind = 1,
  HelpOfferStatus status = HelpOfferStatus.active,
  CommitmentStakeState stakeState = CommitmentStakeState.none,
}) {
  final now = DateTime.utc(2026, 9, 2);
  return (
    beaconId: 'b1',
    userId: _offerer.id,
    user: _offerer,
    message: 'I can step in',
    helpType: null,
    roleLabel: '',
    status: status.smallintValue,
    withdrawReason: null,
    createdAt: now,
    updatedAt: now,
    editedAt: null,
    responseType: null,
    responseUpdatedAt: null,
    responseAuthorUserId: null,
    roomAccess: null,
    admissionAction: null,
    lastDeclineReason: null,
    lastRemoveReason: null,
    stakeState: stakeState.index,
    offerKind: offerKind,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}

Future<FakeBeaconViewCoordinationRepository> _open(
  WidgetTester tester,
  Profile viewer, {
  int offerKind = 1,
  HelpOfferStatus status = HelpOfferStatus.active,
  CommitmentStakeState stakeState = CommitmentStakeState.none,
  bool noRows = false,
  Locale locale = const Locale('en'),
  TextScaler? textScaler,
}) async {
  final beaconRepo = TrackingBeaconRepository()
    ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
      id: id,
      status: offerKind == 1 ? BeaconStatus.enoughHelp : BeaconStatus.open,
      author: _author,
    );
  final coordination = FakeBeaconViewCoordinationRepository(
    rows: noRows
        ? const []
        : [_row(offerKind: offerKind, status: status, stakeState: stakeState)],
  );
  final beaconViewCase = buildTestBeaconViewCase(
    beaconRepo: beaconRepo,
    coordinationRepo: coordination,
  );
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit(viewer)),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHelpOfferTileSheet(
                  context: context,
                  beaconId: 'b1',
                  offerUserId: _offerer.id,
                  myProfile: viewer,
                  beaconViewCase: beaconViewCase,
                  effects: FakeUiEffectPort(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return coordination;
}

final _keep = find.byKey(
  TestIds.key(TestIds.helpOfferKeepStandby(_offerer.id)),
);
final _decline = find.byKey(TestIds.key(TestIds.helpOfferDecline(_offerer.id)));
final _close = find.byKey(
  const ValueKey<String>('help-offer-close-card:offerer-1'),
);

void main() {
  testWidgets('an admitted offer has a close-card action', (tester) async {
    await _open(
      tester,
      _author,
      offerKind: 0,
      stakeState: CommitmentStakeState.acknowledged,
    );

    expect(_close, findsOneWidget);
  });

  testWidgets('a pending offer keeps Accept and Decline and adds close-card', (
    tester,
  ) async {
    await _open(tester, _author, offerKind: 0);

    expect(find.text('Accept'), findsOneWidget);
    expect(_decline, findsOneWidget);
    expect(_close, findsOneWidget);
  });

  testWidgets('a pending backup offer keeps standby and Decline, adds close', (
    tester,
  ) async {
    await _open(tester, _author);

    expect(_keep, findsOneWidget);
    expect(_decline, findsOneWidget);
    expect(_close, findsOneWidget);
  });

  testWidgets('a missing offer still has a close-card action', (tester) async {
    await _open(tester, _author, noRows: true);

    expect(
      find.text(lookupL10n(const Locale('en')).myWorkObligationOfferMissing),
      findsOneWidget,
    );
    expect(_close, findsOneWidget);
  });

  // Built from .values: a new state without a way out fails here.
  for (final stake in CommitmentStakeState.values) {
    for (final status in HelpOfferStatus.values) {
      for (final backup in [false, true]) {
        testWidgets(
          'stake ${stake.name}, ${status.name}, '
          '${backup ? 'backup' : 'ordinary'}: the sheet can close the card',
          (tester) async {
            await _open(
              tester,
              _author,
              offerKind: backup ? 1 : 0,
              status: status,
              stakeState: stake,
            );

            expect(_close, findsOneWidget);
          },
        );
      }
    }
  }
}
