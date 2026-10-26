import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/bloc/closure_author_cubit.dart';
import 'package:tentura/features/closure/ui/screen/closure_author_screen.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

const _tagA = PersonTag(id: 'Ta', name: 'Crew', glyph: 'C', color: 0, ord: 0);
const _card = ValueKey('tag-suggestion-card');
const _button = ValueKey('tag-from-participants');

final class _FakeRepository implements PeopleTagsRepositoryPort {
  bool canSuggest = true;
  final recorded = <String>[];
  List<PersonTagMembers> memberList = [];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      PersonTagSuggestionState(canSuggest: canSuggest, disabled: false);

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    recorded.add(outcome);
    return personTagSuggestionState();
  }

  @override
  Future<List<PersonTag>> personTags() async => const [_tagA];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => memberList;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FakeClosureRepository implements ClosureRepository {
  @override
  Future<ClosureState> fetchState(String beaconId) async => ClosureState(
    epoch: 1,
    status: 1,
    role: ClosureRole.author,
    members: const [
      ClosureMember(id: 'u1', displayName: 'Ann'),
      ClosureMember(id: 'u2', displayName: 'Bob'),
    ],
    closesAt: DateTime.utc(2030, 1, 10, 12),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'auth', displayName: 'Author'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);
}

void main() {
  late _FakeRepository repository;
  late PeopleTagsCase peopleTags;
  late dynamic realtimePort;

  setUp(() async {
    repository = _FakeRepository();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    await peopleTags.load();
    GetIt.I
      ..registerSingleton<PeopleTagsCase>(peopleTags)
      ..registerSingleton<PeopleTagSuggestionCase>(
        PeopleTagSuggestionCase(
          repository,
          env: const Env(),
          logger: Logger('test'),
        ),
      );
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Widget app(Widget child) => MaterialApp(
    theme: TenturaTheme.light(),
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: child),
  );

  group('closure author view', () {
    Future<void> pumpClosure(
      WidgetTester tester, {
      required bool enabled,
    }) async {
      tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = ClosureAuthorCubit(
        ClosureCase(
          _FakeClosureRepository(),
          env: const Env(),
          logger: Logger('test'),
        ),
        beaconId: 'Bclosure00001',
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        app(
          BlocProvider<ClosureAuthorCubit>.value(
            value: cubit,
            child: ClosureAuthorView(peopleTagsEnabled: enabled),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the "Tag them?" card once the server allows it', (
      tester,
    ) async {
      await pumpClosure(tester, enabled: true);
      expect(find.byKey(_card), findsOneWidget);
      expect(find.text('Tag Ann, Bob?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-suggestion-not-now')));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing);
      expect(repository.recorded, ['skipped']);
    });

    testWidgets('shows no card when the server forbids suggestions', (
      tester,
    ) async {
      repository.canSuggest = false;
      await pumpClosure(tester, enabled: true);
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('shows no card behind the gate', (tester) async {
      await pumpClosure(tester, enabled: false);
      expect(find.byKey(_card), findsNothing);
    });
  });

  group('Request People tab', () {
    Future<void> pumpPeople(
      WidgetTester tester, {
      required BeaconKind kind,
      required BeaconAccessLevel? accessLevel,
      bool enabled = true,
      String viewerId = 'auth',
    }) async {
      final t = DateTime.utc(2025);
      final state = BeaconViewState(
        beacon: Beacon(
          id: 'B1',
          title: 'T',
          kind: kind,
          author: const Profile(id: 'auth', displayName: 'Author'),
          createdAt: t,
          updatedAt: t,
          accessLevel: accessLevel,
        ),
        myProfile: Profile(id: viewerId, displayName: 'Viewer'),
      );
      final cubit = _MockBeaconViewCubit(state);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              BlocProvider<BeaconViewCubit>.value(value: cubit),
            ],
            child: Scaffold(
              body: BeaconPeopleTabBody(
                state: state,
                beaconViewCubit: cubit,
                l10n: lookupL10n(const Locale('en')),
                peopleTagsEnabled: enabled,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Tag from participants shows on a Request for a member', (
      tester,
    ) async {
      await pumpPeople(
        tester,
        kind: BeaconKind.request,
        accessLevel: BeaconAccessLevel.member,
      );
      expect(find.byKey(_button), findsOneWidget);
    });

    testWidgets('Tag from participants is hidden from a non-member', (
      tester,
    ) async {
      await pumpPeople(
        tester,
        kind: BeaconKind.request,
        accessLevel: BeaconAccessLevel.observer,
        viewerId: 'other',
      );
      expect(find.byKey(_button), findsNothing);
    });

    testWidgets('Tag from participants is hidden behind the gate', (
      tester,
    ) async {
      await pumpPeople(
        tester,
        kind: BeaconKind.request,
        accessLevel: BeaconAccessLevel.member,
        enabled: false,
      );
      expect(find.byKey(_button), findsNothing);
    });
  });
}
