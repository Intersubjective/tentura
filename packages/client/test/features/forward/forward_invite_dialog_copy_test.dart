import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

// #452: "Invite new person" on the Forward screen opened a dialog titled
// "Invitation code" that never said the invite is for this request, that
// the link works once, or how long it stays valid.

const _enTitle = 'Invite someone to help with this request';

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
  }) async => InvitationEntity(
    id: 'Iabc123def456',
    beaconId: beaconId,
    createdAt: DateTime.utc(2026, 10, 19),
    updatedAt: DateTime.utc(2026, 10, 19),
  );

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

ForwardCubit _forwardCubitWithBeacon() {
  final cubit = ForwardCubit(
    beaconId: 'b1',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );
  final beacon = Beacon.empty.copyWith(
    id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
    title: 'Test beacon',
    context: 'General',
    viewerCanForward: true,
    startAt: DateTime.utc(2025, 5, 12),
    endAt: DateTime.utc(2025, 5, 19),
  );
  cubit.emit(
    ForwardState(
      beaconId: 'b1',
      beacon: beacon,
      candidates: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Clara',
            rScore: 1,
            score: 70,
          ),
        ),
      ],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
  return cubit;
}

String _describeEffects(FakeUiEffectPort effects) => effects.emitted
    .map((e) => e is ShowError ? 'ShowError(${e.error})' : '$e')
    .join(', ');

/// Opens the Forward page in [locale], taps "Invite new person" and
/// returns every string the invite dialog renders, joined by newlines.
Future<String> _openInviteDialog(WidgetTester tester, Locale locale) async {
  // Everything the lazily built InvitationCubit (picker `_invitationCubit`)
  // resolves from GetIt is registered before the page is even pumped; reset
  // after each test so the next one registers on a clean locator.
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
    ..registerSingleton<UiEffectPort>(effects);
  addTearDown(GetIt.I.reset);

  final cubit = _forwardCubitWithBeacon();
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 780)),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: const ForwardBeaconPage(beaconId: 'b1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final inviteButton = find.byKey(TestIds.key(TestIds.forwardInviteNewPerson));
  expect(inviteButton, findsOneWidget);
  // Fire the bar's own callback rather than a synthetic pointer tap, so a
  // hit-test quirk of the test view cannot silently swallow the action.
  final bar = tester.widget<ForwardInviteBar>(find.byType(ForwardInviteBar));
  expect(bar.hasSelection, isFalse);
  bar.onInvite();

  // `_inviteNewPerson` awaits createInvitation, then
  // WidgetsBinding.endOfFrame, then ShareCodeDialog.show: drive explicit,
  // time-advancing frames so every link of that chain gets its frame.
  final shareDialog = find.byType(ShareCodeDialog);
  for (var i = 0; i < 20 && shareDialog.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  // createInvitation swallows failures into a ShowError effect; if the
  // invite was never created, say why instead of "dialog not found".
  expect(
    effects.emitted,
    isEmpty,
    reason: 'invite creation reported: ${_describeEffects(effects)}',
  );
  final pending = tester.takeException();
  expect(pending, isNull, reason: 'exception while opening invite: $pending');

  await tester.pumpAndSettle();

  expect(shareDialog, findsOneWidget);
  final dialog = shareDialog;
  return tester
      .widgetList<RichText>(
        find.descendant(of: dialog, matching: find.byType(RichText)),
      )
      .map((t) => t.text.toPlainText())
      .join('\n');
}

void main() {
  const days = kInvitationDefaultTTL ~/ 24;

  testWidgets('forward invite dialog says it invites someone to this request', (
    tester,
  ) async {
    final text = await _openInviteDialog(tester, const Locale('en'));

    expect(find.text(_enTitle), findsOneWidget);
    expect(find.text('Invitation code'), findsNothing);
    // The body, not just the title: they land on this request and become
    // a connection.
    expect(text, contains('see this request'));
    expect(text, contains('connection'));
  });

  testWidgets('forward invite dialog says it works once and when it expires', (
    tester,
  ) async {
    final text = await _openInviteDialog(tester, const Locale('en'));

    expect(
      text,
      matches(RegExp(r'\bonce\b|single-use|one-time', caseSensitive: false)),
    );
    // Validity comes from the shared invite TTL, not a made-up number.
    expect(text, contains('$days days'));
  });

  testWidgets('forward invite dialog copy is translated in Russian', (
    tester,
  ) async {
    final text = await _openInviteDialog(tester, const Locale('ru'));

    expect(find.text('Код приглашения'), findsNothing);
    expect(find.text(_enTitle), findsNothing);
    expect(text, isNot(contains('this request')));
    // Says, in Russian, that the link works only once, and for how long.
    expect(text, matches(RegExp('один раз|одноразов', caseSensitive: false)));
    expect(text, contains('$days'));
  });
}
