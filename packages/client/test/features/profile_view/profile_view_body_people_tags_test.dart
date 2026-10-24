import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/person_tags_block.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/features/profile_view/ui/widget/profile_info_sheet.dart';
import 'package:tentura/features/profile_view/ui/widget/profile_view_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/fake_person_shared_context_port.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';

const _neighbours = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);

const _viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
const _friend = Profile(id: 'U-peer', displayName: 'Peer', myVote: 1);

void main() {
  group('person tags on the other-person profile', () {
    late _Harness harness;
    late PeopleTagsTestRig rig;
    late ScreenCubit screenCubit;

    setUp(() async {
      harness = _Harness();
      screenCubit = ScreenCubit(FakeUiEffectPort());
      rig = await PeopleTagsTestRig.create(
        FakePeopleTagsRepository(
          tagList: [_neighbours],
          memberList: const [
            PersonTagMembers(tagId: 'Ta', personIds: ['U-peer']),
          ],
          autoByPerson: {
            'U-peer': [
              PersonAutoTagOf(
                kind: PersonAutoTagKind.mutualContact.smallintValue,
                n: 1,
                direction: 0,
              ),
            ],
          },
        ),
      );
      GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
    });

    tearDown(() async {
      await GetIt.I.reset();
      await rig.dispose();
      await screenCubit.close();
      await harness.dispose();
    });

    /// [peopleTagsEnabled] null leaves the body's own default (the gate).
    Future<void> pumpBody(
      WidgetTester tester, {
      Profile subject = _friend,
      Profile viewer = _viewer,
      bool? peopleTagsEnabled,
      Locale locale = const Locale('en'),
    }) async {
      harness.start(id: subject.id, autoFetch: false);
      harness.cubit.emit(
        ProfileViewState(
          profile: subject,
          cues: const PersonCapabilityCues(
            viewerVisible: [
              CapabilityWithSource(slug: 'transport', hasManualLabel: true),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 1400)),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileViewCubit>.value(value: harness.cubit),
                  BlocProvider<ProfileCubit>(
                    create: (_) => _FakeProfileCubit(viewer),
                  ),
                  BlocProvider<ScreenCubit>.value(value: screenCubit),
                ],
                child: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      if (peopleTagsEnabled == null)
                        const ProfileViewBody()
                      else
                        ProfileViewBody(peopleTagsEnabled: peopleTagsEnabled),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder capabilitySection() => find.byWidgetPredicate(
      (w) => w is ProfileFactRow && w.icon == Icons.label_outline,
    );

    testWidgets('shows own tags with ×, automatic tags without ×, and says '
        'only the viewer sees tags', (tester) async {
      await pumpBody(tester, peopleTagsEnabled: true);

      expect(find.text('Your tags'), findsOneWidget);
      expect(find.text('Neighbours'), findsOneWidget);
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Mutual contact'), findsOneWidget);
      expect(find.text('+ Tag'), findsOneWidget);
      expect(find.textContaining('Only you see'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PersonTagsBlock),
          matching: find.byIcon(Icons.close),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the × removes the tag from the person', (tester) async {
      await pumpBody(tester, peopleTagsEnabled: true);

      await tester.tap(
        find.descendant(
          of: find.byType(PersonTagsBlock),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Neighbours'), findsNothing);
      expect(
        rig.repository.appliedOps.single.map(
          (o) => (o.tagId, o.personId, o.add),
        ),
        [('Ta', 'U-peer', false)],
      );
    });

    testWidgets('sits right after the capability section', (tester) async {
      await pumpBody(tester, peopleTagsEnabled: true);

      expect(capabilitySection(), findsOneWidget);
      final capabilityBottom = tester.getBottomLeft(capabilitySection()).dy;
      final blockTop = tester.getTopLeft(find.byType(PersonTagsBlock)).dy;
      expect(blockTop, greaterThanOrEqualTo(capabilityBottom));
    });

    for (final locale in const [Locale('en'), Locale('ru')])
      testWidgets(
        'the capability section never mentions tags (${locale.languageCode})',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await pumpBody(tester, peopleTagsEnabled: true, locale: locale);

          expect(capabilitySection(), findsOneWidget);
          final words = RegExp('tag|тег', caseSensitive: false);
          Iterable<T> inSection<T extends Widget>() => tester.widgetList<T>(
            find.descendant(
              of: capabilitySection(),
              matching: find.byType(T),
            ),
          );
          final texts = <String>[
            // Plain Text (data or spans) and everything built on RichText.
            for (final t in inSection<Text>())
              t.data ?? t.textSpan?.toPlainText() ?? '',
            for (final t in inSection<RichText>()) t.text.toPlainText(),
            for (final t in inSection<Tooltip>()) ?t.message,
            for (final b in inSection<IconButton>()) ?b.tooltip,
            for (final s in inSection<Semantics>())
              ...[
                s.properties.label,
                s.properties.hint,
                s.properties.value,
                s.properties.tooltip,
              ].nonNulls,
          ];
          // What assistive technology reads for the section's subtree.
          void collect(SemanticsNode node) {
            texts
              ..add(node.label)
              ..add(node.hint)
              ..add(node.value)
              ..add(node.tooltip);
            node.visitChildren((child) {
              collect(child);
              return true;
            });
          }

          collect(tester.getSemantics(capabilitySection()));

          expect(texts.where((t) => t.isNotEmpty), isNotEmpty);
          for (final text in texts) {
            expect(words.hasMatch(text), isFalse, reason: text);
          }
          // Before the test ends: tear-downs run after the handle check.
          semantics.dispose();
        },
      );

    testWidgets('is absent on the own profile', (tester) async {
      await pumpBody(
        tester,
        subject: const Profile(id: 'U-viewer', displayName: 'Viewer'),
        peopleTagsEnabled: true,
      );

      expect(find.byType(PersonTagsBlock), findsNothing);
      expect(find.text('Your tags'), findsNothing);
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpBody(tester, peopleTagsEnabled: false);

      expect(find.byType(PersonTagsBlock), findsNothing);
      expect(find.text('Your tags'), findsNothing);
    });

    testWidgets('is absent by default while the feature gate is off', (
      tester,
    ) async {
      await pumpBody(tester);

      expect(find.byType(PersonTagsBlock), findsNothing);
      expect(find.text('Your tags'), findsNothing);
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
      FakePersonSharedContextPort(),
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
