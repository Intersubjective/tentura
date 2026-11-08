import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
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

/// Capabilities lookup that is down: the picker's reasons sheet still
/// opens, without the recipient's existing tags preselected.
class _FailingCapabilityRepository extends Fake
    implements CapabilityRepositoryPort {
  int fetchCuesCalls = 0;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchCues) {
      fetchCuesCalls++;
      return Future<Never>.error(StateError('cues down'));
    }
    return super.noSuchMethod(invocation);
  }
}

// 87a365501 (#1173 split): the failed fetchCues behind "Edit reasons" is
// logged now; it is still swallowed and the sheet still opens.
void main() {
  late PeopleTagsCase peopleTags;
  late TestRealtimeSyncPort realtimePort;
  late _FailingCapabilityRepository capabilities;

  setUp(() async {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
      _FakePeopleTagsRepository(),
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    capabilities = _FailingCapabilityRepository();
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
      ..registerSingleton<PeopleTagsCase>(peopleTags)
      ..registerSingleton<CapabilityRepositoryPort>(capabilities);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  testWidgets('a failed fetchCues is logged as a warning, swallowed, and '
      'the reasons sheet still opens', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final records = <LogRecord>[];
    final logSub = Logger.root.onRecord
        .where((r) => r.loggerName == 'ForwardRecipientPicker')
        .listen(records.add);
    addTearDown(logSub.cancel);
    final cubit = ForwardCubit(
      beaconId: 'B1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'B1',
        beacon: Beacon.empty.copyWith(id: 'B1', title: 'T', needs: {'tools'}),
        activeFilter: ForwardFilter.all,
        candidates: [_candidate('alex'), _candidate('lena')],
        candidatesLoad: const ForwardCandidatesReady(),
        selectedIds: const {'alex'},
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
                sendEnabled: state.selectedIds.isNotEmpty,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = lookupL10n(const Locale('en'));

    final editReasons = find.byTooltip(l10n.forwardReasonPrompt);
    expect(editReasons, findsWidgets);
    await tester.tap(editReasons.first);
    await tester.pumpAndSettle();

    expect(capabilities.fetchCuesCalls, 1);
    expect(records, hasLength(1));
    expect(records.single.level, Level.WARNING);
    expect(records.single.message, 'fetchCues failed');
    expect(records.single.error, isA<StateError>());
    expect(tester.takeException(), isNull);
    expect(
      find.text(l10n.forwardReasonPrompt),
      findsOneWidget,
      reason: 'the reasons sheet opened despite the failure',
    );
    expect(find.text(l10n.buttonSave), findsOneWidget);
  });
}
