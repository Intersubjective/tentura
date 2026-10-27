import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
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

final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  int tagsCalls = 0;
  int membershipsCalls = 0;
  List<PersonTag> tags = const [
    PersonTag(id: 'Tn', name: 'Neighbours', glyph: 'N', color: 0, ord: 0),
    PersonTag(id: 'Tc', name: 'Climbers', glyph: 'C', color: 1, ord: 1),
  ];
  List<PersonTagMembers> members = const [
    PersonTagMembers(tagId: 'Tn', personIds: ['alex', 'blocked', 'sent']),
    PersonTagMembers(tagId: 'Tc', personIds: ['alex', 'lena']),
  ];
  @override
  Future<List<PersonTag>> personTags() async {
    tagsCalls++;
    return tags;
  }

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async {
    membershipsCalls++;
    return members;
  }

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [
    PersonAutoTag(kind: 3, count: 1, showInFilters: true),
    PersonAutoTag(kind: 5, count: 2, showInFilters: true),
  ];

  @override
  Future<List<String>> personAutoTagMembers(int kind) async => switch (kind) {
    3 => ['lena'],
    5 => ['alex', 'o2'],
    _ => [],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ForwardCandidate _candidate(
  String id, {
  double score = 1,
  bool reachable = true,
  CandidateInvolvement involvement = CandidateInvolvement.unseen,
  List<String> topCapabilities = const [],
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: id,
    score: reachable ? score : 0,
    rScore: reachable ? 1 : 0,
  ),
  involvement: involvement,
  topCapabilities: topCapabilities,
);

ValueKey<String> _chip(String tagId) => ValueKey('forward-tag-chip-$tagId');

/// [embedded] is how the Post/Request composer's recipients step hosts the
/// picker (host-provided send button); otherwise the forward screen's form.
Future<ForwardCubit> _pump(
  WidgetTester tester, {
  required bool embedded,
  List<ForwardCandidate>? candidates,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = ForwardCubit(
    beaconId: 'B1',
    debugSkipInitialLoad: true,
    embedded: embedded,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  cubit.emit(
    ForwardState(
      beaconId: 'B1',
      beacon: Beacon.empty.copyWith(id: 'B1', title: 'T', needs: {'tools'}),
      activeFilter: ForwardFilter.all,
      candidates:
          candidates ??
          [
            _candidate('alex'),
            _candidate('lena'),
            _candidate('blocked', reachable: false),
            _candidate('sent', involvement: CandidateInvolvement.forwardedByMe),
            _candidate('o1', topCapabilities: ['tools']),
            _candidate('o2', score: 2),
            _candidate('o3', score: 3),
            _candidate('o4', score: 4),
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
        child: Scaffold(
          body: BlocBuilder<ForwardCubit, ForwardState>(
            builder: (context, state) => ForwardRecipientPicker(
              beaconId: 'B1',
              embedded: embedded,
              onSendPressed: embedded ? () {} : null,
              sendEnabled: state.selectedIds.isNotEmpty,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  late PeopleTagsCase peopleTags;
  late _FakePeopleTagsRepository repository;
  late TestRealtimeSyncPort realtimePort;

  setUp(() async {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    repository = _FakePeopleTagsRepository();
    peopleTags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
      ..registerSingleton<PeopleTagsCase>(peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  testWidgets(
    'a cold forward picker offers own tags and selects their members',
    (tester) async {
      final cubit = await _pump(tester, embedded: false);
      expect(find.byKey(_chip('Tn')), findsOneWidget);
      expect(repository.tagsCalls, 1);
      expect(repository.membershipsCalls, 1);
      await tester.tap(find.byKey(_chip('Tn')));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedIds, {'alex'});
    },
  );
  testWidgets(
    'opening the picker again reuses tags and a realtime hint refreshes them',
    (tester) async {
      await _pump(tester, embedded: false);
      expect(repository.tagsCalls, 1);
      expect(repository.membershipsCalls, 1);
      final cubit = await _pump(tester, embedded: true);
      expect(repository.tagsCalls, 1);
      expect(repository.membershipsCalls, 1);
      repository.tags = const [
        PersonTag(id: 'Tr', name: 'Runners', glyph: 'R', color: 0, ord: 0),
      ];
      repository.members = const [
        PersonTagMembers(tagId: 'Tr', personIds: ['lena']),
      ];
      realtimePort.emitChange(
        RealtimeEntityChange(
          kind: RealtimeEntityKind.personTag,
          aggregateId: 'owner',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
          revision: BigInt.one,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(repository.tagsCalls, 2);
      expect(repository.membershipsCalls, 2);
      expect(find.byKey(_chip('Tn')), findsNothing);
      expect(find.byKey(_chip('Tr')), findsOneWidget);
      await tester.tap(find.byKey(_chip('Tr')));
      await tester.pumpAndSettle();
      expect(cubit.state.selectedIds, {'lena'});
    },
  );
}
