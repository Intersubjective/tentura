import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_inbound_source.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_band_strip.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
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

ForwardState _state(BeaconKind kind) => ForwardState(
  beaconId: 'B1',
  beacon: Beacon.empty.copyWith(
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
  BeaconKind kind,
) async {
  tester.view
    ..physicalSize = const Size(1200, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = _SendRecordingCubit();
  addTearDown(cubit.close);
  cubit.emit(_state(kind));
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
        child: const Scaffold(
          body: ForwardRecipientPicker(beaconId: 'B1'),
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
  });

  group('ForwardRecipientPicker for a Post', () {
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
  });
}
