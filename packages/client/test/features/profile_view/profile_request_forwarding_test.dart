import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_delivery_result.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/features/profile_view/ui/widget/profile_view_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_person_shared_context_port.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/people_tags_widget_harness.dart';

void main() {
  group('Profile request forwarding action', () {
    const viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
    const reachablePerson = Profile(
      id: 'U-peer',
      displayName: 'Peer',
      score: 1,
      rScore: 1,
    );
    const locale = Locale('ru');
    final l10n = lookupL10n(locale);
    late _ProfileViewBodyHarness harness;
    late FakeUiEffectPort effects;
    late ScreenCubit screenCubit;

    setUp(() {
      effects = FakeUiEffectPort();
      screenCubit = ScreenCubit(effects);
    });

    tearDown(() async {
      await screenCubit.close();
      await harness.dispose();
    });

    Future<void> pumpProfile(WidgetTester tester, Profile subject) async {
      harness = _ProfileViewBodyHarness()..start(id: subject.id);
      harness.cubit.emit(ProfileViewState(profile: subject));
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileViewCubit>.value(value: harness.cubit),
                BlocProvider<ProfileCubit>(
                  create: (_) => _FakeProfileCubit(viewer),
                ),
                BlocProvider<ScreenCubit>.value(value: screenCubit),
              ],
              child: const Scaffold(
                body: CustomScrollView(slivers: [ProfileViewBody()]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'reachable other person shows one localized forward request action',
      (tester) async {
        await pumpProfile(tester, reachablePerson);

        // #501: the action opens a list of Requests and Posts alike.
        expect(l10n.labelForward, 'Переслать');
        expect(find.text(l10n.labelForward), findsOneWidget);
      },
    );

    testWidgets('own profile hides the forward request action', (tester) async {
      await pumpProfile(tester, viewer);

      expect(find.text(l10n.labelForward), findsNothing);
      expect(effects.emitted.whereType<NavigatePush>(), isEmpty);
    });

    for (final visibility in [
      ('neither person can see the other', 0.0, 0.0),
      ('only the viewer can see the person', 1.0, 0.0),
      ('only the person can see the viewer', 0.0, 1.0),
    ]) {
      testWidgets('${visibility.$1} hides the forward request action', (
        tester,
      ) async {
        await pumpProfile(
          tester,
          reachablePerson.copyWith(
            score: visibility.$2,
            rScore: visibility.$3,
          ),
        );

        expect(find.text(l10n.labelForward), findsNothing);
        expect(effects.emitted.whereType<NavigatePush>(), isEmpty);
      });
    }

    testWidgets('paused recipient hides the forward request action', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        reachablePerson.copyWith(
          availability: Availability(
            resumeOn: availabilityTodayUtc().add(const Duration(days: 3)),
          ),
        ),
      );

      expect(find.text(l10n.labelForward), findsNothing);
    });

    testWidgets('limited recipient still shows the forward request action', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        reachablePerson.copyWith(
          availability: const Availability(isLimited: true),
        ),
      );

      expect(find.text(l10n.labelForward), findsOneWidget);
    });

    testWidgets(
      'forward request action opens the person-forward path for the viewed person',
      (tester) async {
        await pumpProfile(tester, reachablePerson);

        final action = find.text(l10n.labelForward);
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();

        expect(
          effects.emitted.whereType<NavigatePush>().map((e) => e.path).toList(),
          ['$kPathForwardPerson/${reachablePerson.id}'],
        );
      },
    );

    testWidgets(
      'forwarding from a profile sends only the chosen request to that person',
      (tester) async {
        await pumpProfile(tester, reachablePerson);
        final forwardRepository = _RecordingForwardRepository();
        addTearDown(forwardRepository.dispose);
        GetIt.I.registerSingleton<ContactNameStore>(harness.contactStore);
        addTearDown(() => GetIt.I.unregister<ContactNameStore>());
        final otherRequest = Beacon.empty.copyWith(
          id: 'B-other',
          title: 'Another request',
          author: viewer,
        );
        final chosenRequest = Beacon.empty.copyWith(
          id: 'B-chosen',
          title: 'Chosen request',
          author: viewer,
        );
        final personForwardCase = PersonForwardCase(
          forwardRepository,
          _OpenRequestsRepository([otherRequest, chosenRequest]),
          harness.profiles,
          harness.authLocal,
          harness.contactsCase,
          env: const Env(),
          logger: Logger('ProfileRequestForwardingTest'),
        );

        final action = find.text(l10n.labelForward);
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        final destination = effects.emitted
            .whereType<NavigatePush>()
            .single
            .path;
        expect(destination, '$kPathForwardPerson/${reachablePerson.id}');

        // Follow the navigation effect with the existing flow, preserving its
        // recipient argument. The forwarding repository is the mocked I/O seam.
        final personId = Uri.parse(destination).pathSegments.last;
        final forwardCubit = PersonForwardCubit(
          personId: personId,
          personForwardCase: personForwardCase,
          effects: effects,
        );
        addTearDown(forwardCubit.close);
        final router = RootStackRouter.build(routes: []);
        addTearDown(router.dispose);
        await tester.pumpPeopleTagsWidget(
          MaterialApp(
            locale: locale,
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<PersonForwardCubit>.value(value: forwardCubit),
                  BlocProvider<ScreenCubit>.value(value: screenCubit),
                ],
                child: RouterScope(
                  controller: router,
                  stateHash: 0,
                  inheritableObserversBuilder: () => const [],
                  child: StackRouterScope(
                    controller: router,
                    stateHash: 0,
                    child: PersonForwardScreen(personId: personId),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(forwardCubit.state.person?.id, reachablePerson.id);
        expect(
          find.text(l10n.beaconForwardToPersonTitle(reachablePerson.shownName)),
          findsOneWidget,
        );
        expect(forwardRepository.sent, isEmpty);
        await tester.tap(find.text(chosenRequest.title));
        await tester.pumpAndSettle();
        expect(forwardCubit.state.selectedBeaconId, chosenRequest.id);
        final send = find.widgetWithText(
          FilledButton,
          l10n.beaconForwardPersonSend,
        );
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();

        expect(forwardRepository.sent, hasLength(1));
        final sent = forwardRepository.sent.single;
        expect(sent.beaconId, chosenRequest.id);
        expect(sent.recipientIds, [reachablePerson.id]);
        expect(sent.note, isNull);
        expect(forwardCubit.state.lastDeliveredBeaconId, chosenRequest.id);
      },
    );
  });
}

class _OpenRequestsRepository implements BeaconRepository {
  _OpenRequestsRepository(this.requests);
  final List<Beacon> requests;

  @override
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = 5,
  }) async => requests.where((request) => request.author.id == profileId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingForwardRepository implements ForwardRepository {
  final sent = <({String beaconId, List<String> recipientIds, String? note})>[];

  @override
  Stream<String> get forwardChanges => const Stream.empty();

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(
    Beacon beacon,
  ) async => (
    beacon: beacon,
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    declinedOfferIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: <String, bool>{},
    myForwardedRecipientRejected: <String, bool>{},
  );

  @override
  Future<ForwardDeliveryResult> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
    List<String>? attributionParentEdgeIds,
    Map<String, ({String? tier, bool isExploration})>? recipientBandProvenance,
  }) async {
    sent.add((beaconId: beaconId, recipientIds: recipientIds, note: note));
    return ForwardDeliveryResult(
      batchId: 'edge-1',
      deliveredRecipientIds: recipientIds,
      availabilitySkippedRecipientIds: const [],
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileCubit implements ProfileCubit {
  _FakeProfileCubit(Profile profile) : _state = ProfileState(profile: profile);

  final ProfileState _state;

  @override
  ProfileState get state => _state;

  @override
  Stream<ProfileState> get stream => Stream.value(_state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileViewBodyHarness {
  _ProfileViewBodyHarness() {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    authCase = buildTestAuthCase(authLocal, EmptyAuthRemote());
    contactsCase = ContactsCase(
      contactsRepository,
      authCase,
      contactStore,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
    case_ = ProfileViewCase(
      profiles,
      likes,
      capabilities,
      contactsCase,
      realtimeCase,
      sharedContexts,
      env: const Env(),
      logger: Logger('test'),
    );
  }

  final authLocal = StreamingAuthLocal('U-viewer');
  final contactsRepository = FakeContactsRepository();
  final contactStore = ContactNameStore();
  final sharedContexts = FakePersonSharedContextPort();
  final profiles = _FakeProfileRepository();
  final likes = _FakeLikeRepository();
  final capabilities = _FakeCapabilityRepository();
  final blockCase = ControllableBlockCase();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final ProfileViewCase case_;
  ProfileViewCubit? _cubit;

  ProfileViewCubit get cubit => _cubit!;

  void start({required String id}) {
    _cubit = ProfileViewCubit.test(
      id: id,
      profileViewCase: case_,
      blockCase: blockCase,
      effects: FakeUiEffectPort(),
      autoFetch: false,
    );
  }

  Future<void> dispose() async {
    await _cubit?.close();
    await contactsCase.dispose();
    await realtimePort.dispose();
    await contactStore.dispose();
    await profiles.dispose();
    await likes.dispose();
    await capabilities.dispose();
    await authLocal.dispose();
  }
}

final class _FakeProfileRepository implements ProfileRepositoryPort {
  final person = const Profile(
    id: 'U-peer',
    displayName: 'Peer',
    score: 1,
    rScore: 1,
  );

  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<Profile> fetchById(String id) async => const Profile();

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async =>
      ids.contains(person.id) ? [person] : [];

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    dynamic image,
    bool updateHandle = false,
    String? handle,
  }) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) async {}

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) async {}

  @override
  Future<void> resumeAvailability({required String profileId}) async {}

  @override
  Future<void> dispose() => _changes.close();
}

final class _FakeLikeRepository implements LikeRemoteRepository {
  final _changes = StreamController<RepositoryEvent<Likable>>.broadcast();

  @override
  Stream<RepositoryEvent<Likable>> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) async =>
      const [];

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
