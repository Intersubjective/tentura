import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/post_bud_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/beacon_create_case_factory.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import 'fake_beacon_ports.dart';

const kBudPostId = 'post-1';
const kBudSourceMessageId = 'msg-1';

const kBudContext = BeaconCreationContextPromotedChild(
  parentBeaconId: kBudPostId,
  sourceMessageId: kBudSourceMessageId,
);

PostBudInviteCandidate budCandidate(
  String userId, {
  bool hasWritten = false,
  bool pretick = false,
  PostBudInviteOutcome outcome = PostBudInviteOutcome.invited,
  String? viaUserId,
}) => PostBudInviteCandidate(
  userId: userId,
  warm: hasWritten,
  outcome: outcome,
  pretick: pretick,
  hasWritten: hasWritten,
  viaUserId: viaUserId,
);

final class BudCall {
  const BudCall({
    required this.clientCommandId,
    required this.title,
    required this.description,
    required this.isDiscoverable,
    required this.invitees,
    required this.closePost,
    required this.needs,
    this.factIds,
  });

  final String clientCommandId;
  final String title;
  final String? description;
  final bool isDiscoverable;
  final List<PostBudInvitee> invitees;
  final bool closePost;
  final String? needs;

  /// Null when the caller sent no fact ids at all.
  final List<String>? factIds;
}

class FakePostBudPort implements PostBudPort {
  List<PostBudInviteCandidate> candidates = const [];

  final calls = <BudCall>[];

  Exception? budError;

  /// When set, `inviteCandidates` waits for it before answering.
  Completer<void>? candidatesGate;

  /// When set, `inviteCandidates` throws it.
  Exception? candidatesError;

  /// When set, `budFromPost` waits for it before answering.
  Completer<void>? gate;

  PostBudResult result = const PostBudResult(
    outcome: PostBudOutcome.created,
    childBeaconId: 'child-1',
  );

  @override
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
  }) async {
    await candidatesGate?.future;
    final error = candidatesError;
    if (error != null) throw error;
    return candidates;
  }

  @override
  Future<PostBudResult> budFromPost({
    required String postId,
    required String clientCommandId,
    required String title,
    String? sourceMessageId,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool isDiscoverable = false,
    List<PostBudInvitee> invitees = const [],
    bool closePost = false,
    List<String>? factIds,
  }) async {
    calls.add(
      BudCall(
        clientCommandId: clientCommandId,
        title: title,
        description: description,
        isDiscoverable: isDiscoverable,
        invitees: invitees,
        closePost: closePost,
        needs: needs,
        factIds: factIds,
      ),
    );
    await gate?.future;
    final error = budError;
    if (error != null) throw error;
    return result;
  }
}

class FakeBudProfiles extends Mock implements ProfileRepositoryPort {
  FakeBudProfiles([this.profiles = const []]);

  final List<Profile> profiles;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final p in profiles)
      if (ids.contains(p.id)) p,
  ];
}

/// The Post the bud starts from; by default the budder (`me`) started it,
/// so they may close it (#666).
Beacon budPost({
  BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
  String authorId = 'me',
}) => Beacon.empty.copyWith(
  id: kBudPostId,
  kind: BeaconKind.post,
  forwardPolicy: forwardPolicy,
  author: Profile(id: authorId),
);

/// Everything a bud-mode [BeaconCreateCubit] reads, with fakes.
final class BudHarness {
  BudHarness({
    String sourceText = 'Need a ladder\nFor Saturday at noon.',
    Beacon? parent,
    List<Profile> profiles = const [],
  }) : write = FakeBeaconWritePort(beacon: parent ?? budPost()),
       hierarchy = FakeBeaconHierarchyRepositoryPort(
         promotionSource: BeaconPromotionSource(
           sourceBeaconId: kBudPostId,
           sourceMessageId: kBudSourceMessageId,
           textPreview: sourceText,
           author: const BeaconHierarchyOwnerSummary(
             id: 'me',
             displayName: 'Me',
           ),
         ),
       ),
       profiles = FakeBudProfiles(profiles);

  final FakeBeaconWritePort write;
  final FakeBeaconHierarchyRepositoryPort hierarchy;
  final FakeBudProfiles profiles;
  final port = FakePostBudPort();

  BeaconCreateCase get createCase =>
      buildBeaconCreateCase(beacons: write);

  PostBudCase get postBudCase => PostBudCase(
    port,
    OpIdService(),
    env: const Env(),
    logger: Logger('post-bud-test'),
  );

  MessagePrefillCase get prefillCase => MessagePrefillCase(hierarchy);

  BeaconCreateCubit cubit({
    required UiEffectPort effects,
    bool enabled = true,
  }) => BeaconCreateCubit(
    beaconCreateCase: createCase,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      hierarchy,
      createCase: createCase,
      beacons: write,
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
    messagePrefillCase: prefillCase,
    postBudCase: postBudCase,
    postBuddingEnabled: enabled,
    childCreationContext: kBudContext,
    effects: effects,
  );
}

/// The id the bud tests sign in as; [budPost] is started by them by default.
const kBudViewerId = 'me';

class _NoForwardRepository implements ForwardRepository {
  @override
  Stream<String> get forwardChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFactCards implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [FakeBudProfiles] as the server returns them to a Post member: every
/// member resolves, and both sides can see each other (`my_vote` 1,
/// `trusts_viewer`), like the `UsersFetchByIds` rows of the wire tests.
class _MemberProfiles extends Mock implements ProfileRepositoryPort {
  _MemberProfiles(this._known);

  final FakeBudProfiles _known;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async {
    final byId = {
      for (final p in await _known.fetchProfilesByIds(ids)) p.id: p,
    };
    return [
      for (final id in ids)
        (byId[id] ?? Profile(id: id)).copyWith(
          myVote: 1,
          subjectExplicitlyTrustsViewer: true,
        ),
    ];
  }
}

class BudProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class BudInvitationRepository extends Fake implements InvitationRepository {
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

/// The real [ForwardCase] the invite step's ForwardCubit loads Post members
/// through, over the harness's fake bud port and profiles. Call [dispose]
/// when done.
final class BudForward {
  BudForward._(this.forwardCase, this.authLocal, this._dispose);

  final ForwardCase forwardCase;

  /// Signed in as [kBudViewerId] (or the id given to [start]).
  final StreamingAuthLocal authLocal;

  final Future<void> Function() _dispose;

  Future<void> dispose() => _dispose();

  static Future<BudForward> start(
    BudHarness h, {
    String viewerId = kBudViewerId,
  }) async {
    final authLocal = StreamingAuthLocal();
    final contactsRepo = FakeContactsRepository()
      ..fetchMineHandler = () async => {};
    final store = ContactNameStore();
    if (!GetIt.I.isRegistered<ContactNameStore>()) {
      GetIt.I.registerSingleton<ContactNameStore>(store);
    }
    final contactsCase = ContactsCase(
      contactsRepo,
      buildTestAuthCase(authLocal, EmptyAuthRemote()),
      store,
      buildTestRealtimeSync().case_,
      env: const Env(),
      logger: Logger('post-bud-forward'),
    );
    final ready = contactsRepo.nextSync();
    authLocal.emit(viewerId);
    await ready.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    final forwardCase = ForwardCase(
      _NoForwardRepository(),
      authLocal,
      _NoFactCards(),
      _MemberProfiles(h.profiles),
      contactsCase,
      noopBlockCase(),
      postBudPort: h.port,
    );
    return BudForward._(forwardCase, authLocal, () async {
      await contactsCase.dispose();
      await store.dispose();
    });
  }

  /// A loaded invite-step [ForwardCubit] for [kBudPostId], as the screen
  /// builds it.
  Future<ForwardCubit> inviteCubit() async {
    final cubit = ForwardCubit(
      beaconId: '',
      budPostId: kBudPostId,
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
        .timeout(const Duration(seconds: 10));
    return cubit;
  }
}

/// Registers what the bud create screen's invite step reads from GetIt: the
/// signed-in [AuthCase], the [ForwardCase] its ForwardCubit loads through,
/// and the invitations repository the picker listens to.
Future<BudForward> registerBudInvitePicker(
  WidgetTester tester,
  BudHarness h, {
  String viewerId = kBudViewerId,
}) async {
  final forward = (await tester.runAsync(
    () => BudForward.start(h, viewerId: viewerId),
  ))!;
  addTearDown(() => tester.runAsync(forward.dispose));
  GetIt.I
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(forward.authLocal, EmptyAuthRemote()),
    )
    ..registerSingleton<ForwardCase>(forward.forwardCase)
    ..registerSingleton<InvitationRepository>(BudInvitationRepository());
  return forward;
}

/// Bounded pumps with real time in between, so the fake ports answer.
Future<void> settleBud(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _BudContextRepository extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class BudRouter extends Mock implements StackRouter {
  final opened = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }
}

typedef BudScreen = ({
  BudHarness h,
  BeaconCreateCubit cubit,
  BudRouter router,
  FakeUiEffectPort effects,
});

/// The bud create screen for [h]'s Post, signed in as [kBudViewerId], on its
/// first (form) step.
Future<BudScreen> pumpBudCreateScreen(
  WidgetTester tester,
  BudHarness h, {
  Locale locale = const Locale('en'),
  Size surface = const Size(800, 1600),
}) async {
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<Env>(const Env())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ContextRepository>(_BudContextRepository());
  addTearDown(GetIt.I.reset);
  await registerBudInvitePicker(tester, h);
  final cubit = h.cubit(effects: effects);
  addTearDown(cubit.close);

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = BudRouter();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: surface),
        child: TenturaResponsiveScope(
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(create: (_) => ContextCubit()),
                  BlocProvider<ProfileCubit>.value(value: BudProfileCubit()),
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                ],
                child: const BeaconCreateScreen(
                  parentBeaconId: kBudPostId,
                  sourceMessageId: kBudSourceMessageId,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settleBud(tester);
  return (h: h, cubit: cubit, router: router, effects: effects);
}
