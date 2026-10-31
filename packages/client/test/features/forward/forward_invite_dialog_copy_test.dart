import 'dart:async';

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

const _servedTtlHours = 48;

const _enTitle = 'Invite someone to help with this request';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  _FakeInvitationRepository({Future<int> Function()? ttlHours})
    : _ttlHours = ttlHours ?? (() async => _servedTtlHours);

  final Future<int> Function() _ttlHours;

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

  /// By default the server serves a 48 h invitation lifetime.
  @override
  Future<int> fetchTtlHours() => _ttlHours();

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
Future<String> _openInviteDialog(
  WidgetTester tester,
  Locale locale, {
  Future<int> Function()? ttlHours,
}) async {
  // Everything the lazily built InvitationCubit (picker `_invitationCubit`)
  // resolves from GetIt is registered before the page is even pumped; reset
  // after each test so the next one registers on a clean locator.
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<InvitationRepository>(
      _FakeInvitationRepository(ttlHours: ttlHours),
    )
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
  return _dialogText(tester);
}

/// Every string the open invite dialog currently renders, newline-joined.
String _dialogText(WidgetTester tester) => tester
    .widgetList<RichText>(
      find.descendant(
        of: find.byType(ShareCodeDialog),
        matching: find.byType(RichText),
      ),
    )
    .map((t) => t.text.toPlainText())
    .join('\n');

/// "N days" as a whole phrase: `2 days` must not match inside `12 days`.
RegExp _days(int n) => RegExp('\\b$n days\\b');

/// What the invite says when the server has not (yet) said how long it lasts.
const _defaultDays = kInvitationDefaultTTL ~/ 24;

void main() {
  const days = _servedTtlHours ~/ 24;

  // Guards the "served, not default" assertions below against going vacuous.
  test('the served lifetime used by these tests differs from the default', () {
    expect(_defaultDays, isNot(days));
  });

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
    // Validity comes from the TTL the server serves, not the compiled
    // default.
    expect(text, matches(_days(days)));
    expect(text, isNot(matches(_days(_defaultDays))));
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
    // The served 48 h, in Russian plural form for 2.
    expect(text, contains('действует 2 дня.'));
  });

  group('while the served lifetime is not known', () {
    testWidgets('invite dialog states the compiled default when the lookup '
        'fails', (tester) async {
      final text = await _openInviteDialog(
        tester,
        const Locale('en'),
        ttlHours: () async => throw StateError('network'),
      );

      expect(text, matches(_days(_defaultDays)));
      expect(text, isNot(matches(_days(days))));
    });

    testWidgets('invite dialog opens at once with the compiled default while '
        'the lookup is pending, then shows the served lifetime', (
      tester,
    ) async {
      final served = Completer<int>();
      addTearDown(() {
        if (!served.isCompleted) served.complete(_servedTtlHours);
      });

      final waiting = await _openInviteDialog(
        tester,
        const Locale('en'),
        ttlHours: () => served.future,
      );
      expect(waiting, matches(_days(_defaultDays)));
      expect(waiting, isNot(matches(_days(days))));

      served.complete(_servedTtlHours);
      await tester.pumpAndSettle();

      final arrived = _dialogText(tester);
      expect(arrived, matches(_days(days)));
      expect(arrived, isNot(matches(_days(_defaultDays))));
    });
  });
}
