import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

// #453: on Forward, the search icon opened a full-screen overlay on top of
// the picker. On wide screens it split into a result list plus a detail pane
// that repeated the same person row, and the overlay covered the footer, so
// there was no Forward button until you went Back.
//
// Rule: search filters the existing recipient list in place (scoped to the
// active tab), each matching person appears once, and the footer Forward
// button stays on screen and usable while searching.

const _desktop = Size(1280, 800);
const _phone = Size(390, 844);

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

ForwardCubit _cubit() {
  return ForwardCubit(
    beaconId: 'b1',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  )..emit(
    ForwardState(
      beaconId: 'b1',
      beacon: Beacon.empty.copyWith(
        id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
        title: 'Test beacon',
        context: 'General',
        viewerCanForward: true,
        startAt: DateTime.utc(2025, 5, 12),
        endAt: DateTime.utc(2025, 5, 19),
      ),
      candidates: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Clara',
            rScore: 1,
            score: 70,
          ),
        ),
        ForwardCandidate(
          profile: Profile(
            id: 'u2',
            displayName: 'Zed',
            rScore: 1,
            score: 20,
          ),
        ),
        // Already forwarded by me: lives on the "Already involved" tab, so a
        // search on "Not yet seen" must not surface it.
        ForwardCandidate(
          profile: Profile(
            id: 'u3',
            displayName: 'Clarisse',
            rScore: 1,
            score: 50,
          ),
          involvement: CandidateInvolvement.forwardedByMe,
        ),
      ],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
}

Future<ForwardCubit> _pumpForward(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  GetIt.I
    ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort());
  addTearDown(GetIt.I.reset);

  final cubit = _cubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ForwardCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        ],
        child: const ForwardBeaconPage(beaconId: 'b1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// The recipient search field, found by its existing hint
/// (`forwardOverlaySearchHint`, "search recipients").
final _searchField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'search recipients',
);

Finder _row(String name) => find.widgetWithText(ForwardRecipientRow, name);

Finder get _forwardButton =>
    find.widgetWithText(OutlinedButton, 'Forward to 1');

Future<void> _openSearchAndType(WidgetTester tester, String query) async {
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
  expect(_searchField, findsOneWidget);
  await tester.enterText(_searchField, query);
  await tester.pumpAndSettle();
}

Future<void> _searchSelectsAndKeepsFooter(
  WidgetTester tester,
  Size size,
) async {
  final cubit = await _pumpForward(tester, size);

  // Precondition: both unseen people are listed before searching.
  expect(_row('Clara'), findsOneWidget);
  expect(_row('Zed'), findsOneWidget);

  await _openSearchAndType(tester, 'cla');

  // One row per match, no second pane repeating it; non-matches are gone
  // from the list (filtered in place, not covered by another view).
  expect(_row('Clara'), findsOneWidget);
  expect(_row('Zed'), findsNothing);
  // Scoped to the active tab ("Not yet seen").
  expect(_row('Clarisse'), findsNothing);

  await tester.tap(
    find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
  );
  await tester.pumpAndSettle();
  expect(cubit.state.selectedIds, {'u1'});
  expect(_row('Clara'), findsOneWidget);

  // The footer action is on screen (not under an overlay) and enabled
  // while search is still active.
  expect(_searchField, findsOneWidget);
  expect(_forwardButton.hitTestable(), findsOneWidget);
  expect(tester.widget<OutlinedButton>(_forwardButton).onPressed, isNotNull);
}

void main() {
  testWidgets('desktop: Forward search filters in place, one row, footer '
      'Forward button usable', (tester) async {
    await _searchSelectsAndKeepsFooter(tester, _desktop);
  });

  testWidgets('phone: Forward search filters in place, one row, footer '
      'Forward button usable', (tester) async {
    await _searchSelectsAndKeepsFooter(tester, _phone);
  });

  testWidgets('clearing the search restores the whole list once, selection '
      'kept', (tester) async {
    final cubit = await _pumpForward(tester, _desktop);
    await _openSearchAndType(tester, 'cla');
    await tester.tap(
      find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_searchField, '');
    await tester.pumpAndSettle();

    expect(_row('Clara'), findsOneWidget);
    expect(_row('Zed'), findsOneWidget);
    expect(_row('Clarisse'), findsNothing);
    expect(cubit.state.selectedIds, {'u1'});
    expect(_forwardButton.hitTestable(), findsOneWidget);
  });
}
