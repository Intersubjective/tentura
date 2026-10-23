// #596: a backup offer opened from My Work had no way to answer it, so the
// author's obligation never ended. The sheet now offers «Keep as standby»
// and «Decline» (with a reason); either one closes the sheet.

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

FakeHelpOfferCoordinationRow _row({int offerKind = 1}) {
  final now = DateTime.utc(2026, 9, 2);
  return (
    beaconId: 'b1',
    userId: _offerer.id,
    user: _offerer,
    message: 'I can step in',
    helpType: null,
    roleLabel: '',
    status: 0,
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
    stakeState: 0,
    offerKind: offerKind,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}

Future<FakeBeaconViewCoordinationRepository> _open(
  WidgetTester tester,
  Profile viewer, {
  int offerKind = 1,
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
    rows: [_row(offerKind: offerKind)],
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

void main() {
  testWidgets('the author sees Keep as standby and Decline', (tester) async {
    await _open(tester, _author);

    expect(_keep, findsOneWidget);
    expect(find.text('Keep as standby'), findsOneWidget);
    expect(_decline, findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('Keep as standby answers the offer and closes the sheet', (
    tester,
  ) async {
    final coordination = await _open(tester, _author);

    await tester.tap(_keep);
    await tester.pumpAndSettle();

    expect(coordination.keepHelpOfferStandbyCalls, [
      (beaconId: 'b1', offerUserId: _offerer.id),
    ]);
    expect(coordination.declineHelpOfferCalls, isEmpty);
    expect(_keep, findsNothing);
    // The confirmation lands on the app's messenger, so it outlives the
    // sheet; the bar renders its text as RichText.
    expect(find.text('Kept as standby', findRichText: true), findsOneWidget);
  });

  // Review of #707: «Оставлен(а) запасным» named the person with a gendered
  // form; the confirmation now names the offer.
  testWidgets('the Russian confirmation names the offer', (tester) async {
    await _open(tester, _author, locale: const Locale('ru'));

    await tester.tap(_keep);
    await tester.pumpAndSettle();

    expect(
      find.text('Отклик оставлен запасным', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('Decline asks for a reason, then closes the sheet', (
    tester,
  ) async {
    final coordination = await _open(tester, _author);

    await tester.tap(_decline);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.admissionReasonInput)),
      'We are covered',
    );
    await tester.pump();
    await tester.tap(find.byKey(TestIds.key(TestIds.admissionReasonSubmit)));
    await tester.pumpAndSettle();

    expect(coordination.declineHelpOfferCalls, [
      (beaconId: 'b1', offerUserId: _offerer.id, reason: 'We are covered'),
    ]);
    expect(coordination.keepHelpOfferStandbyCalls, isEmpty);
    expect(_keep, findsNothing);
  });

  testWidgets('someone who is not the author sees neither', (tester) async {
    await _open(tester, const Profile(id: 'other-1', displayName: 'Other'));

    expect(_keep, findsNothing);
    expect(_decline, findsNothing);
  });

  // Review of #707: at a large text scale the two Russian labels did not fit
  // on one line of a phone-wide sheet and the row overflowed; they now wrap.
  testWidgets('both answers fit a phone-wide sheet at a large text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _open(
      tester,
      _author,
      locale: const Locale('ru'),
      textScaler: const TextScaler.linear(2),
    );

    // At this size a row of the offer tile above the answers overflows too
    // (pre-existing, not part of this fix), so the test asserts the answers'
    // own geometry: with the old Row, Decline ended well past the edge.
    tester.takeException();
    expect(_keep, findsOneWidget);
    expect(_decline, findsOneWidget);
    for (final button in [_keep, _decline]) {
      final rect = tester.getRect(button);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
  });

  // Guard: an ordinary offer keeps Accept and Decline, without the backup
  // answer.
  testWidgets('an ordinary offer has no Keep as standby', (tester) async {
    await _open(tester, _author, offerKind: 0);

    expect(_keep, findsNothing);
    expect(find.text('Accept'), findsOneWidget);
    expect(_decline, findsOneWidget);
  });
}
