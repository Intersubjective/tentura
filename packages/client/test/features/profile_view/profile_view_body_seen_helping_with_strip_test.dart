import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/features/profile_view/ui/widget/profile_view_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('ProfileViewBody seen helping with strip', () {
    late _Harness harness;
    late FakeUiEffectPort effects;
    late ScreenCubit screenCubit;

    setUp(() {
      harness = _Harness();
      effects = FakeUiEffectPort();
      screenCubit = ScreenCubit(effects);
    });

    tearDown(() async {
      await screenCubit.close();
      await harness.dispose();
    });

    Future<void> pumpBody(
      WidgetTester tester, {
      required Profile subject,
      required Profile viewer,
      required ProfileViewState viewState,
    }) async {
      harness.start(id: subject.id, autoFetch: false);
      harness.cubit.emit(viewState.copyWith(profile: subject));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 900)),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileViewCubit>.value(value: harness.cubit),
                  BlocProvider<ProfileCubit>(
                    create: (_) => _FakeProfileCubit(viewer),
                  ),
                  BlocProvider<ScreenCubit>.value(value: screenCubit),
                ],
                child: const Scaffold(
                  body: CustomScrollView(
                    slivers: [ProfileViewBody()],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hides strip when subjectiveTags is empty', (tester) async {
      const viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
      const subject = Profile(id: 'U-peer', displayName: 'Peer', myVote: 1);
      final l10n = lookupL10n(const Locale('en'));

      await pumpBody(
        tester,
        subject: subject,
        viewer: viewer,
        viewState: const ProfileViewState(subjectiveTags: []),
      );

      expect(find.text(l10n.capabilityCueSeenHelpingWith('')), findsNothing);
    });

    testWidgets('shows strip with up to three subjective tag slugs', (
      tester,
    ) async {
      const viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
      const subject = Profile(id: 'U-peer', displayName: 'Peer', myVote: 1);
      final l10n = lookupL10n(const Locale('en'));
      const tags = [
        TagProjection(
          subjectUserId: 'U-peer',
          tagSlug: 'transport',
          tier: ProjectionTier.networkOutcome,
        ),
        TagProjection(
          subjectUserId: 'U-peer',
          tagSlug: 'pets',
          tier: ProjectionTier.ownOutcome,
        ),
        TagProjection(
          subjectUserId: 'U-peer',
          tagSlug: 'legal_navigation',
          tier: ProjectionTier.networkOutcome,
        ),
      ];

      await pumpBody(
        tester,
        subject: subject,
        viewer: viewer,
        viewState: const ProfileViewState(subjectiveTags: tags),
      );

      expect(
        find.text(l10n.capabilityCueSeenHelpingWith(
          '${l10n.capabilityTagTransport} · '
          '${l10n.capabilityTagPets} · '
          '${l10n.capabilityTagLegalNavigation}',
        )),
        findsOneWidget,
      );
    });
  });
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

class _Harness {
  _Harness() {
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
      env: const Env(),
      logger: Logger('test'),
    );
  }

  final authLocal = StreamingAuthLocal();
  final contactsRepository = FakeContactsRepository();
  final contactStore = ContactNameStore();
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

  void start({required String id, bool autoFetch = true}) {
    _cubit = ProfileViewCubit.test(
      id: id,
      profileViewCase: case_,
      blockCase: blockCase,
      effects: FakeUiEffectPort(),
      autoFetch: autoFetch,
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
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<Profile> fetchById(String id) async => const Profile();

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => const [];

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
  List<TagProjection> subjectiveTags = const [];

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) async =>
      subjectiveTags;

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
