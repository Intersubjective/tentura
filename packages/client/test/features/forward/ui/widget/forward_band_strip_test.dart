import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_band_strip.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../../../ui/effect/fake_ui_effect_port.dart';

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
  Future<void> dispose() async {}
}

TagProjection _label(String slug, ProjectionTier tier) => TagProjection(
  subjectUserId: 'subject',
  tagSlug: slug,
  tier: tier,
);

ForwardBandRow _evidenceRow({
  required String userId,
  required ProjectionTier tier,
  List<TagProjection>? labels,
}) => ForwardBandRow(
  userId: userId,
  rowTier: tier,
  labels: labels ?? [_label('transport', tier)],
  rank: 0,
);

ForwardCandidate _candidate(String id, String name) => ForwardCandidate(
  profile: Profile(id: id, displayName: name),
);

Widget _wrapBand({
  required List<ForwardBandRow> band,
  required List<ForwardCandidate> candidates,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      ],
      child: Scaffold(
        body: SingleChildScrollView(
          child: ForwardBandStrip(
            band: band,
            candidates: candidates,
            selectedIds: const {},
            onToggle: (_) {},
            onEditReasons: (_) {},
            recipientReasons: const {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<UiEffectPort>()) {
      GetIt.I.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    }
    if (!GetIt.I.isRegistered<InvitationRepository>()) {
      GetIt.I.registerSingleton<InvitationRepository>(
        _FakeInvitationRepository(),
      );
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<InvitationRepository>()) {
      await GetIt.I.unregister<InvitationRepository>();
    }
    if (GetIt.I.isRegistered<UiEffectPort>()) {
      await GetIt.I.unregister<UiEffectPort>();
    }
  });

  testWidgets('ownOutcome tier renders expected copy', (tester) async {
    await tester.pumpWidget(
      _wrapBand(
        band: [_evidenceRow(userId: 'u1', tier: ProjectionTier.ownOutcome)],
        candidates: [_candidate('u1', 'Carol')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You worked together on Transport'), findsOneWidget);
  });

  testWidgets('ownRouting tier renders expected copy', (tester) async {
    await tester.pumpWidget(
      _wrapBand(
        band: [
          _evidenceRow(
            userId: 'u1',
            tier: ProjectionTier.ownRouting,
            labels: [_label('tools', ProjectionTier.ownRouting)],
          ),
        ],
        candidates: [_candidate('u1', 'Alex')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You\'ve routed Tools here'), findsOneWidget);
  });

  testWidgets('networkOutcome tier renders joined label copy', (tester) async {
    await tester.pumpWidget(
      _wrapBand(
        band: [
          _evidenceRow(
            userId: 'u1',
            tier: ProjectionTier.networkOutcome,
            labels: [
              _label('transport', ProjectionTier.networkOutcome),
              _label('tools', ProjectionTier.networkOutcome),
            ],
          ),
        ],
        candidates: [_candidate('u1', 'Alex')],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Seen helping with Transport · Tools'),
      findsOneWidget,
    );
  });

  testWidgets('networkSeed tier renders expected copy', (tester) async {
    await tester.pumpWidget(
      _wrapBand(
        band: [_evidenceRow(userId: 'u1', tier: ProjectionTier.networkSeed)],
        candidates: [_candidate('u1', 'Julia')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggested for Transport'), findsOneWidget);
  });

  testWidgets('empty band renders no band section widgets', (tester) async {
    final cubit = ForwardCubit(
      beaconId: 'beacon-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'beacon-1',
        beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Need help'),
        candidates: [_candidate('u1', 'Carol')],
        band: const [],
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

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
            body: ForwardRecipientPicker(
              beaconId: 'beacon-1',
              embedded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ForwardBandStrip), findsNothing);
    expect(find.text('For this request'), findsNothing);
  });

  testWidgets('exploration divider separates evidence and exploration rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapBand(
        band: [
          _evidenceRow(userId: 'u1', tier: ProjectionTier.networkOutcome),
          ForwardBandRow(
            userId: 'u2',
            rank: 4,
            isExploration: true,
          ),
        ],
        candidates: [
          _candidate('u1', 'Alex'),
          _candidate('u2', 'Peter'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New to this kind of request'), findsOneWidget);
    expect(find.text('Seen helping with Transport'), findsOneWidget);
    expect(find.text('Peter'), findsOneWidget);
    expect(find.textContaining('helping'), findsOneWidget);
  });

  testWidgets('band member is not duplicated in main recipient list', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'beacon-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'beacon-1',
        beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Need help'),
        candidates: [
          _candidate('carol', 'Carol Dup'),
          _candidate('other', 'Other Person'),
        ],
        band: [
          _evidenceRow(userId: 'carol', tier: ProjectionTier.ownOutcome),
        ],
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

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
            body: ForwardRecipientPicker(
              beaconId: 'beacon-1',
              embedded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Carol Dup'), findsOneWidget);
    expect(find.text('Other Person'), findsOneWidget);
    expect(find.text('You worked together on Transport'), findsOneWidget);
  });
}
