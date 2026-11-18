// Real HTTP-shaped responses through Ferry, repositories, ForwardCase, cubit and picker.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/users_fetch_by_ids_wire.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpost00000001';
const _members = [
  'Umember00001',
  'Umember00002',
  'Umember00003',
  'Umember00004',
];
const _alreadyInvited = 'Uinvited00001';
const _viaId = 'Uvia000000001';
const _scores = [0.1, 0.3, 0.6, 0.9];
const _names = ['Member A', 'Match B', 'Member C', 'Match D'];

Map<String, dynamic> _wireCandidate(int index, {bool through = false}) => {
  '__typename': 'PostBudInviteCandidate',
  'userId': _members[index],
  'warm': !through,
  'outcome': 'invited',
  'pretick': false,
  'viaUserId': through ? _viaId : null,
  'hasWritten': index < 2,
};

Map<String, dynamic> _inviteCandidates(bool through) => {
  '__typename': 'query_root',
  'postBudInviteCandidates': [
    _wireCandidate(0, through: through),
    {
      ..._wireCandidate(0),
      'userId': _alreadyInvited,
      'outcome': 'alreadyInvited',
    },
    _wireCandidate(1, through: through),
    if (!through) ...[_wireCandidate(2), _wireCandidate(3)],
  ],
};

Map<String, dynamic> _usersAnswer(WireSent request) {
  final answer = cappedUsersAnswer(request);
  for (final row in (answer['user'] as List).cast<Map<String, dynamic>>()) {
    final index = _members.indexOf(row['id'] as String);
    if (index < 0) continue;
    row['display_name'] = _names[index];
    row['scores'] = [
      {'src_score': 1.0, 'dst_score': _scores[index]},
    ];
  }
  return answer;
}

Map<String, dynamic> _forwardCandidates() => {
  '__typename': 'query_root',
  'forwardCandidates': [
    for (final (index, score) in [0.2, 0.9, 0.5].indexed)
      {
        ...wireUserRow(_members[index]),
        '__typename': 'v2_user',
        'displayName': _names[index],
        'shares_active_context': false,
        'scores': [
          {'src_score': 1.0, 'dst_score': score},
        ],
      },
  ],
};

class _NoBeaconRepository implements BeaconRepository {
  @override
  Future<Beacon> fetchBeaconById(String id) async =>
      Beacon.empty.copyWith(id: id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

/// A postBudInvite [ForwardCubit] for [_postId], loaded over the fake HTTP
/// transport through the real repositories and [ForwardCase].
Future<ForwardCubit> _loadInviteCubit({
  bool through = false,
  bool checkForwardOrder = false,
}) async {
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository()
    ..fetchMineHandler = () async => {};
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('BudInvitePickerWireTest'),
  );
  addTearDown(() async {
    await contactsCase.dispose();
    await store.dispose();
  });
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('Uviewer000001');
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  late ForwardCubit cubit;
  await withRemoteWire(
    const {},
    <WireSent>[],
    (remote) async {
      final forwardCase = ForwardCase(
        ForwardRepository(
          remote,
          _NoBeaconRepository(),
          buildTestRealtimeSync().port,
        ),
        authLocal,
        _FakeBeaconFactCardRepository(),
        ProfileRepository(remote),
        contactsCase,
        noopBlockCase(),
        postBudPort: PostBudRepository(remote),
        env: const Env(),
        logger: Logger('BudInvitePickerWireTest'),
      );
      if (checkForwardOrder) {
        for (final profile in [
          ForwardTargetProfile.request,
          ForwardTargetProfile.post,
        ]) {
          final forwardCubit = ForwardCubit(
            beaconId: 'Brequest00001',
            targetProfile: profile,
            forwardCase: forwardCase,
            effects: FakeUiEffectPort(),
          );
          try {
            await forwardCubit.stream
                .firstWhere(
                  (s) => s.candidatesLoad is! ForwardCandidatesLoading,
                )
                .timeout(const Duration(seconds: 20));
            expect(
              forwardCubit.state.candidatesLoad,
              isA<ForwardCandidatesReady>(),
            );
            forwardCubit.setFilter(ForwardFilter.all);
            final expected = [_members[1], _members[2], _members[0]];
            expect(
              forwardCubit.state.visibleRecipients.map((c) => c.id),
              expected,
              reason: '${profile.name} forwarding keeps descending MeritRank',
            );
            expect(
              forwardCubit.state.computeBeaconListSections().recommended.map(
                (c) => c.id,
              ),
              expected,
            );
            expect(forwardCubit.state.visibleRecipients.map((c) => c.mrScore), [
              0.9,
              0.5,
              0.2,
            ]);
          } finally {
            await forwardCubit.close();
          }
        }
      }
      cubit = ForwardCubit(
        beaconId: '',
        budPostId: _postId,
        targetProfile: ForwardTargetProfile.postBudInvite,
        forwardCase: forwardCase,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      await cubit.stream
          .firstWhere(
            (s) =>
                s.candidatesLoad is ForwardCandidatesReady ||
                s.candidatesLoad is ForwardCandidatesEmpty ||
                s.candidatesLoad is ForwardCandidatesError,
          )
          .timeout(const Duration(seconds: 20));
    },
    responseFor: (request) async => switch (request.operationName) {
      'PostBudInviteCandidates' => _inviteCandidates(through),
      'UsersFetchByIds' => _usersAnswer(request),
      'ForwardCandidatesFetch' => _forwardCandidates(),
      'BeaconInvolvementData' => {
        '__typename': 'query_root',
        'beaconInvolvement': {
          '__typename': 'v2_BeaconInvolvement',
          'forwardedToIds': <String>[],
          'helpOfferedIds': <String>[],
          'withdrawnIds': <String>[],
          'declinedOfferIds': <String>[],
          'rejectedIds': <String>[],
          'watchingIds': <String>[],
          'onwardForwarderIds': <String>[],
          'myForwardedRecipients': <Object>[],
        },
      },
      _ => const <String, dynamic>{},
    },
  );
  addTearDown(cubit.close);
  return cubit;
}

Future<ForwardCubit> _pumpLoadedPicker(
  WidgetTester tester, {
  bool through = false,
  bool phone = false,
  Locale locale = const Locale('en'),
}) async {
  if (phone) {
    await usePhoneSurface(tester);
  } else {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final cubit = (await tester.runAsync(
    () => _loadInviteCubit(through: through),
  ))!;
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
        child: const Scaffold(
          body: ForwardRecipientPicker(
            beaconId: '',
            embedded: true,
            copyProfile: ForwardTargetProfile.postBudInvite,
            recipientNoteHint: 'Note for the invite',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void _expectLoadedMembers(ForwardCubit cubit, {bool through = false}) {
  expect(cubit.state.candidatesLoad, isA<ForwardCandidatesReady>());
  final expected = through ? _members.take(2).toList() : _members;
  expect(cubit.state.candidates.map((c) => c.id), expected);
  expect(
    cubit.state.candidates.map((c) => c.mrScore),
    through ? _scores.take(2).toList() : _scores,
  );
  expect(
    cubit.state.candidates.map((c) => c.id),
    isNot(contains(_alreadyInvited)),
  );
}

void _expectRowsInOrder(WidgetTester tester, List<String> ids) {
  final rows = find.byType(ForwardRecipientRow);
  expect(rows, findsNWidgets(ids.length));
  final topToBottom = rows.evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  expect(
    topToBottom.map((e) => (e.widget as ForwardRecipientRow).candidate.id),
    ids,
  );
}

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
  });
  tearDown(() async => GetIt.I.reset());

  group('Post bud invite candidates preserve server order', () {
    test(
      'lists all invitable writers and nonwriters in server order despite rising MeritRank',
      () async {
        final cubit = await _loadInviteCubit();
        _expectLoadedMembers(cubit);
        expect(cubit.state.visibleRecipients.map((c) => c.id), _members);
      },
    );

    test(
      'selecting a member keeps the server order of every recipient',
      () async {
        final cubit = await _loadInviteCubit();
        _expectLoadedMembers(cubit);
        expect(cubit.state.selectedIds, isEmpty);
        cubit.toggleSelection(_members[2]);
        expect(cubit.state.selectedIds, {_members[2]});
        expect(cubit.state.visibleRecipients.map((c) => c.id), _members);
      },
    );

    test(
      'preserves invite order while Request and Post forwarding keep descending MeritRank',
      () async {
        final cubit = await _loadInviteCubit(checkForwardOrder: true);
        _expectLoadedMembers(cubit);
        expect(cubit.state.visibleRecipients.map((c) => c.id), _members);
      },
    );

    testWidgets('direct members render top to bottom in server order', (
      tester,
    ) async {
      final cubit = await _pumpLoadedPicker(tester);
      _expectLoadedMembers(cubit);
      for (final name in _names) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      _expectRowsInOrder(tester, _members);
    });

    testWidgets(
      'members introduced through someone render in server order within their group',
      (tester) async {
        final cubit = await _pumpLoadedPicker(tester, through: true);
        _expectLoadedMembers(cubit, through: true);
        for (final candidate in cubit.state.candidates) {
          expect(candidate.reach?.via.single.id, _viaId);
        }
        expect(find.textContaining('Name of $_viaId'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        _expectRowsInOrder(tester, _members.take(2).toList());
      },
    );

    testWidgets(
      'matching invite rows keep server order on a Russian phone layout',
      (tester) async {
        final cubit = await _pumpLoadedPicker(
          tester,
          phone: true,
          locale: const Locale('ru'),
        );
        _expectLoadedMembers(cubit);
        await tester.enterText(find.byType(TextField).first, 'Match');
        await tester.pumpAndSettle();
        expect(find.text(_names[1]), findsOneWidget);
        expect(find.text(_names[3]), findsOneWidget);
        expect(find.text(_names[0]), findsNothing);
        expect(find.text(_names[2]), findsNothing);
        expect(tester.takeException(), isNull);
        _expectRowsInOrder(tester, [_members[1], _members[3]]);
      },
    );
  });
}
