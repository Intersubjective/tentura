import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_inbound_source.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_band_strip.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/forward/ui/widget/lineage_forward_section.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

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
  Future<void> dispose() async {}
}

/// Cubit with two inbound sources and a recorded send, no network.
class _SendRecordingCubit extends ForwardCubit {
  _SendRecordingCubit()
    : super(
        beaconId: 'B1',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
        clock: () => DateTime.utc(2026, 10, 26, 12),
      );

  int inboundSourceFetches = 0;
  int forwardCalls = 0;
  List<String>? lastAttributionIds;

  @override
  Future<List<ForwardInboundSource>> fetchInboundSources() async {
    inboundSourceFetches++;
    return [
      ForwardInboundSource(
        edgeId: 'E1',
        senderId: 'S1',
        senderName: 'Sender One',
        createdAt: DateTime.utc(2026),
        isSuggestedSource: true,
      ),
      ForwardInboundSource(
        edgeId: 'E2',
        senderId: 'S2',
        senderName: 'Sender Two',
        createdAt: DateTime.utc(2026),
        isSuggestedSource: false,
      ),
    ];
  }

  @override
  Future<bool> forward({List<String>? attributionParentEdgeIds}) async {
    forwardCalls++;
    lastAttributionIds = attributionParentEdgeIds;
    return true;
  }
}

const _alex = Profile(id: 'u1', displayName: 'Alex', score: 10, rScore: 1);
const _lena = Profile(id: 'u2', displayName: 'Lena', score: 5, rScore: 1);
const _max = Profile(id: 'u3', displayName: 'Max', score: 8, rScore: 1);

/// A null [kind] leaves the beacon unloaded, as in the Post composer.
ForwardState _state(BeaconKind? kind) => ForwardState(
  beaconId: 'B1',
  beacon: kind == null
      ? null
      : Beacon.empty.copyWith(
          id: 'B1',
          title: 'Subject',
          kind: kind,
          needs: const {'tools'},
        ),
  candidates: const [
    ForwardCandidate(profile: _alex),
    ForwardCandidate(profile: _lena),
  ],
  band: const [ForwardBandRow(userId: 'u1')],
  lineageSuggestions: const [
    ForwardCandidate(
      profile: _lena,
      lineageReasonCode: 'prior_forward',
    ),
  ],
  recipientReasons: const {
    'u1': ['knows_topic'],
  },
  selectedIds: const {'u1'},
  skippedPersonalNoteIds: const {'u1'},
  candidatesLoad: const ForwardCandidatesReady(),
);

Future<_SendRecordingCubit> _pump(
  WidgetTester tester,
  BeaconKind? kind, {
  ForwardTargetProfile? copyProfile,
  Beacon? beacon,
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = const Size(1200, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = _SendRecordingCubit();
  addTearDown(cubit.close);
  final state = _state(kind);
  cubit.emit(beacon == null ? state : state.copyWith(beacon: beacon));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ForwardCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        ],
        child: Scaffold(
          body: ForwardRecipientPicker(
            beaconId: 'B1',
            copyProfile: copyProfile,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
  });

  tearDown(() async {
    await GetIt.I.unregister<InvitationRepository>();
    await GetIt.I.unregister<UiEffectPort>();
  });

  testWidgets('Post subtitle shows two hours remaining and still sends', (
    tester,
  ) async {
    final cubit = await _pump(
      tester,
      BeaconKind.post,
      locale: const Locale('ru'),
      beacon: Beacon.empty.copyWith(
        id: 'B1',
        title: 'Subject',
        kind: BeaconKind.post,
        expiresAt: DateTime.utc(2026, 10, 26, 14),
      ),
    );

    expect(find.text('Subject · осталось 2 ч'), findsOneWidget);
    await tester.tap(find.byKey(TestIds.key(TestIds.forwardSubmit)));
    await tester.pumpAndSettle();
    expect(cubit.forwardCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final entry in {
    BeaconStatus.open: 'Открыт',
    BeaconStatus.needsMoreHelp: 'Нужна ещё или другая помощь',
    BeaconStatus.closed: 'Закрыт',
  }.entries) {
    testWidgets('Request subtitle retains lifecycle ${entry.key.name}', (
      tester,
    ) async {
      await _pump(
        tester,
        BeaconKind.request,
        locale: const Locale('ru'),
        beacon: Beacon.empty.copyWith(
          id: 'B1',
          title: 'Subject',
          status: entry.key,
        ),
      );
      expect(find.text('Subject · ${entry.value}'), findsOneWidget);
      expect(find.textContaining('осталось'), findsNothing);
    });
  }

  group('ForwardRecipientPicker for a Request', () {
    testWidgets('shows band strip, lineage header and reasons button', (
      tester,
    ) async {
      await _pump(tester, BeaconKind.request);

      expect(find.byType(ForwardBandStrip), findsOneWidget);
      expect(find.byType(LineageForwardSectionHeader), findsOneWidget);
      expect(find.byType(BeaconRequirementsBar), findsOneWidget);
      expect(
        find.byTooltip('Why are you forwarding to this person?'),
        findsWidgets,
      );
    });

    // Guard: an unloaded beacon with no host profile stays a Request.
    testWidgets('an unloaded beacon keeps the reasons button and band', (
      tester,
    ) async {
      await _pump(tester, null);

      expect(find.byType(ForwardBandStrip), findsOneWidget);
      expect(
        find.byTooltip('Why are you forwarding to this person?'),
        findsWidgets,
      );
    });

    testWidgets('title and scope tab hints speak of the request', (
      tester,
    ) async {
      await _pump(tester, BeaconKind.request);

      expect(find.text('Forward request'), findsOneWidget);
      expect(
        find.byTooltip("People who haven't seen this request yet"),
        findsOneWidget,
      );
      expect(
        find.byTooltip("People already in this request's forward chain"),
        findsOneWidget,
      );
    });

    testWidgets('asks for attribution when several inbound sources exist', (
      tester,
    ) async {
      final cubit = await _pump(tester, BeaconKind.request);

      await tester.tap(find.byKey(TestIds.key(TestIds.forwardSubmit)));
      await tester.pumpAndSettle();

      expect(cubit.inboundSourceFetches, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Sender One'), findsOneWidget);
    });

    testWidgets('ticking 1 person shows per-recipient note field and skip action', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = _SendRecordingCubit();
      addTearDown(cubit.close);
      final state = ForwardState(
        beaconId: 'B1',
        beacon: Beacon.empty.copyWith(
          id: 'B1',
          title: 'Subject',
          kind: BeaconKind.request,
        ),
        candidates: const [
          ForwardCandidate(profile: _alex),
          ForwardCandidate(profile: _lena),
        ],
        selectedIds: const {'u1'},
        candidatesLoad: const ForwardCandidatesReady(),
      );
      cubit.emit(state);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'B1',
                recipientNoteHint: 'Add a note for this person (optional)',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PerRecipientNoteInput), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Add a note for this person (optional)'),
        findsOneWidget,
      );
      expect(find.byTooltip('Skip personal note'), findsOneWidget);
    });
  });

  group('ForwardRecipientPicker for a Post', () {
    // #455: the post's recipient step talked about "this request".
    testWidgets('title and scope tab hints speak of the post', (tester) async {
      await _pump(tester, BeaconKind.post);

      expect(find.text('Forward post'), findsOneWidget);
      expect(
        find.byTooltip("People who haven't seen this post yet"),
        findsOneWidget,
      );
      expect(
        find.byTooltip("People already in this post's forward chain"),
        findsOneWidget,
      );
    });

    testWidgets('the Post composer sets the copy before a beacon is loaded', (
      tester,
    ) async {
      await _pump(tester, null, copyProfile: ForwardTargetProfile.post);

      expect(
        find.byTooltip("People who haven't seen this post yet"),
        findsOneWidget,
      );
      expect(
        find.byTooltip("People already in this post's forward chain"),
        findsOneWidget,
      );
    });

    // #501 (QA 7.52.0): New post › Recipients still offered the reason
    // button and the band, as the draft has no beacon and the forward state
    // read as a Request; the host's copyProfile now gates them too.
    testWidgets('the Post composer offers no reasons button', (tester) async {
      await _pump(tester, null, copyProfile: ForwardTargetProfile.post);

      expect(
        find.byTooltip('Why are you forwarding to this person?'),
        findsNothing,
      );
    });

    testWidgets('the Post composer shows no band or lineage', (tester) async {
      await _pump(tester, null, copyProfile: ForwardTargetProfile.post);

      expect(find.byType(ForwardBandStrip), findsNothing);
      expect(find.byType(LineageForwardSectionHeader), findsNothing);
    });

    testWidgets('hides the band strip', (tester) async {
      await _pump(tester, BeaconKind.post);

      expect(find.byType(ForwardBandStrip), findsNothing);
    });

    testWidgets('hides the lineage suggestions header', (tester) async {
      await _pump(tester, BeaconKind.post);

      expect(find.byType(LineageForwardSectionHeader), findsNothing);
    });

    testWidgets('offers no per-recipient reasons button', (tester) async {
      await _pump(tester, BeaconKind.post);

      expect(
        find.byTooltip('Why are you forwarding to this person?'),
        findsNothing,
      );
    });

    testWidgets('hides the beacon requirements bar', (tester) async {
      await _pump(tester, BeaconKind.post);

      expect(find.byType(BeaconRequirementsBar), findsNothing);
    });

    testWidgets('sends without opening the attribution dialog', (
      tester,
    ) async {
      final cubit = await _pump(tester, BeaconKind.post);

      await tester.tap(find.byKey(TestIds.key(TestIds.forwardSubmit)));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Sender One'), findsNothing);
      expect(cubit.forwardCalls, 1);
      expect(cubit.lastAttributionIds, isNull);
    });

    testWidgets('post profile with 3 selected people shows no note fields or skip action', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = _SendRecordingCubit();
      addTearDown(cubit.close);
      const state = ForwardState(
        beaconId: 'B1',
        candidates: [
          ForwardCandidate(profile: _alex),
          ForwardCandidate(profile: _lena),
          ForwardCandidate(profile: _max),
        ],
        selectedIds: {'u1', 'u2', 'u3'},
        candidatesLoad: ForwardCandidatesReady(),
      );
      cubit.emit(state);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'B1',
                copyProfile: ForwardTargetProfile.post,
                recipientNoteHint: 'Add a note for this person (optional)',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PerRecipientNoteInput), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Add a note for this person (optional)'),
        findsNothing,
      );
      expect(find.byTooltip('Skip personal note'), findsNothing);
    });
  });
}
