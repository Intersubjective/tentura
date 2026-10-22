import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../features/beacon_create/fake_beacon_ports.dart';
import '../ui/effect/fake_ui_effect_port.dart';
import 'constellation_store_fixture.dart';
import 'fake_clock_port.dart';
import 'fake_wake_up_port.dart';
import 'test_forward_case.dart';
import 'test_realtime_sync.dart';

/// Viewer of the composer screen harness.
const composerHarnessEgo = Profile(id: 'ego', displayName: 'Ego');

/// A field whose people are [peers], each trusted by the viewer; every call
/// builds a fresh object, so a store reads it as a changed field.
ConstellationField composerHarnessField({
  List<String> peers = const ['a'],
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 9),
  context: '',
  peers: [for (final id in peers) ConstellationPerson(id: id)],
  edges: [
    for (final id in peers)
      ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
  ],
  requests: const [
    ConstellationRequest(
      id: 'req-a',
      authorId: 'a',
      title: 'Need tools',
      status: 0,
      needs: ['tools'],
    ),
  ],
);

/// Serves [fieldBuilder] on every read and counts the reads.
final class ComposerHarnessRepository implements ConstellationRepositoryPort {
  ComposerHarnessRepository([ConstellationField Function()? fieldBuilder])
    : fieldBuilder = fieldBuilder ?? composerHarnessField;

  ConstellationField Function() fieldBuilder;

  int fetches = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetches++;
    return fieldBuilder();
  }
}

/// Forward candidates the composer may address; counts how often they are read.
final class ComposerHarnessForwardRepository implements ForwardRepository {
  ComposerHarnessForwardRepository({this.candidateIds = const ['a']});

  final List<String> candidateIds;

  int candidateReads = 0;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    candidateReads++;
    return [for (final id in candidateIds) Profile(id: id)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ComposerHarnessContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  ComposerHarnessContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

/// Loads the field once and returns the cubit; closes it when the test ends.
Future<ConstellationCubit> loadComposerHarnessCubit(
  ConstellationRepositoryPort repository, {
  ComposerHarnessForwardRepository? forward,
  ConstellationStoreFixture? fixture,
}) async {
  final cubit = ConstellationCubit(
    case_:
        (fixture ??
                ConstellationStoreFixture(
                  repository,
                  accountId: composerHarnessEgo.id,
                ))
            .store,
    viewer: composerHarnessEgo,
    forwardCase: buildTestForwardCase(
      forward ?? ComposerHarnessForwardRepository(),
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

/// A store whose clock, wake-ups and field hints the test drives by hand.
({
  ConstellationStoreFixture fixture,
  FakeClockPort clock,
  FakeWakeUpPort wakeUp,
  TestRealtimeSyncPort realtime,
})
composerHarnessControlledStore(ConstellationRepositoryPort repository) {
  final clock = FakeClockPort(DateTime.utc(2026, 10, 9));
  final wakeUp = FakeWakeUpPort();
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  return (
    fixture: ConstellationStoreFixture(
      repository,
      accountId: composerHarnessEgo.id,
      clock: clock,
      wakeUp: wakeUp,
      realtime: realtime.case_,
    ),
    clock: clock,
    wakeUp: wakeUp,
    realtime: realtime.port,
  );
}

/// The composer as the screen builds it. A [peopleSnapshot] replaces the
/// fixed `a` addressee; closes the composer when the test ends.
ConstellationComposerCubit buildComposerHarnessComposer({
  Future<({Map<String, Offset> positions, Set<String> eligible})> Function()?
  peopleSnapshot,
  Set<String> eligible = const {'a'},
}) {
  final composer = ConstellationComposerCubit(
    positions: const {},
    eligible: eligible,
    peopleSnapshot: peopleSnapshot,
    createCubitFactory: (kind) => BeaconCreateCubit(
      kind: kind,
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    ),
    forwardCubitFactory: (id) =>
        ForwardCubit(beaconId: id, effects: FakeUiEffectPort()),
    personName: (_) => 'Ann',
  );
  addTearDown(composer.close);
  return composer;
}

Future<void> pumpComposerHarnessScreen(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required ConstellationComposerCubit composer,
}) async {
  const size = Size(1280, 800);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<ConstellationComposerCubit>.value(value: composer),
              BlocProvider(create: (_) => HomeTabReselectCubit()),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => ComposerHarnessContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: const ConstellationScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
