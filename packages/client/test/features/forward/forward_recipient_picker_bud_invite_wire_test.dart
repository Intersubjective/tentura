// The Post→Request invite step end to end on the client: the real Ferry link
// chain (only HTTP is faked) answers `PostBudInviteCandidates` and
// `UsersFetchByIds`, the real ForwardRepository/ForwardCase map them, a
// postBudInvite ForwardCubit loads them, and the shared ForwardRecipientPicker
// shows them without the Forward-only chrome.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_bottom_composer.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/forward/ui/widget/forward_scope_links.dart';
import 'package:tentura/features/forward/ui/widget/forward_tag_picker.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/users_fetch_by_ids_wire.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpost00000001';
const _warmA = 'Umember00001';
const _warmB = 'Umember00002';
const _viaMember = 'Umember00003';
const _viaId = 'Uvia000000001';

String _nameOf(String id) => 'Name of $id';

Map<String, dynamic> _wireCandidate(String userId, {String? viaUserId}) => {
  '__typename': 'PostBudInviteCandidate',
  'userId': userId,
  'warm': viaUserId == null,
  'outcome': 'invited',
  'pretick': false,
  'viaUserId': viaUserId,
  'hasWritten': false,
};

Map<String, dynamic> _inviteCandidates(bool empty) => {
  '__typename': 'query_root',
  'postBudInviteCandidates': empty
      ? <Object>[]
      : [
          _wireCandidate(_warmA),
          _wireCandidate(_warmB),
          _wireCandidate(_viaMember, viaUserId: _viaId),
        ],
};

class _NoBeaconRepository implements BeaconRepository {
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
Future<ForwardCubit> _loadInviteCubit({required bool empty}) async {
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
      'PostBudInviteCandidates' => _inviteCandidates(empty),
      'UsersFetchByIds' => cappedUsersAnswer(request),
      _ => const <String, dynamic>{},
    },
  );
  addTearDown(cubit.close);
  return cubit;
}

Future<ForwardCubit> _pumpLoadedPicker(
  WidgetTester tester, {
  required bool empty,
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = const Size(1200, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = (await tester.runAsync(() => _loadInviteCubit(empty: empty)))!;
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

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('Invite picker loaded from the server', () {
    testWidgets(
      'shows the Post members with their names and «via» person, lets the '
      'user tick and note them, and has no Forward-only chrome',
      (tester) async {
        final cubit = await _pumpLoadedPicker(tester, empty: false);

        for (final id in [_warmA, _warmB, _viaMember]) {
          expect(find.text(_nameOf(id)), findsOneWidget);
        }
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is ForwardRecipientRow && w.candidate.id == _viaMember,
            ),
            matching: find.textContaining(_nameOf(_viaId)),
          ),
          findsOneWidget,
        );

        expect(
          find.byType(ForwardInviteBar, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardTagPicker, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardScopeLinks, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardBottomComposer, skipOffstage: false),
          findsNothing,
        );

        final row = find.byKey(TestIds.key(TestIds.forwardRecipient(_warmB)));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(cubit.state.selectedIds, {_warmB});

        final en = lookupL10n(const Locale('en'));
        await tester.tap(
          find.byTooltip(en.forwardAddPersonalNoteForName(_nameOf(_warmB))),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PerRecipientNoteInput), findsOneWidget);
      },
    );

    testWidgets('a Post with no one left to invite shows the invite empty '
        'state', (tester) async {
      await _pumpLoadedPicker(tester, empty: true);

      expect(find.text('No one else in this post to invite'), findsOneWidget);
      expect(find.text('No one to send to yet'), findsNothing);
    });
  });
}
