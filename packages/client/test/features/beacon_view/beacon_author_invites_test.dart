// Plan D4: a Request budded from a Post. The parent link reads «Вырос из
// поста» only when the Post is readable; the author's People tab lists the
// snapshot observers and invites (status, note, withdraw, «Позвать»); nobody
// else sees the section or asks for it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/author_invite_port.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_parent_link.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_author_invites_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_surface.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../inbox/author_invite_test_support.dart' show buildActorProfiles;
import '../../support/people_tags_widget_harness.dart';

const _author = Profile(id: 'auth', displayName: 'Author');
const _ann = Profile(id: 'Uann', displayName: 'Ann');
const _bob = Profile(id: 'Ubob', displayName: 'Bob');
const _cat = Profile(id: 'Ucat', displayName: 'Cat');
const _dan = Profile(id: 'Udan', displayName: 'Dan');

final _t = DateTime.utc(2026, 10, 11);

/// Scriptable [AuthorInvitePort] for the People tab (plan D4).
final class _Port implements AuthorInvitePort {
  List<AuthorInvite> invites = const [];
  List<String> observers = const [];
  PostBudInviteOutcome createOutcome = PostBudInviteOutcome.invited;

  final reads = <String>[];
  final created = <String>[];
  final withdrawn = <String>[];

  @override
  Future<List<AuthorInvite>> beaconInvites({required String beaconId}) async {
    reads.add('invites:$beaconId');
    return invites;
  }

  @override
  Future<List<String>> budObservers({required String beaconId}) async {
    reads.add('observers:$beaconId');
    return observers;
  }

  @override
  Future<AuthorInviteCreateResult> create({
    required String beaconId,
    required String userId,
    String? note,
  }) async {
    created.add(userId);
    if (createOutcome != PostBudInviteOutcome.invited) {
      return AuthorInviteCreateResult(outcome: createOutcome);
    }
    invites = [
      ...invites,
      AuthorInvite(
        id: 'I-$userId',
        beaconId: beaconId,
        inviteeId: userId,
        status: AuthorInviteStatus.pending,
        createdAt: _t.add(const Duration(hours: 1)),
      ),
    ];
    return AuthorInviteCreateResult(
      outcome: PostBudInviteOutcome.invited,
      inviteId: 'I-$userId',
    );
  }

  @override
  Future<AuthorInvite> withdraw({required String inviteId}) async {
    withdrawn.add(inviteId);
    invites = [
      for (final i in invites)
        i.id == inviteId ? i.copyWith(status: AuthorInviteStatus.withdrawn) : i,
    ];
    return AuthorInvite(
      id: inviteId,
      beaconId: 'B1',
      status: AuthorInviteStatus.withdrawn,
    );
  }

  @override
  Future<AuthorInvite> accept({required String inviteId}) =>
      throw UnimplementedError();

  @override
  Future<AuthorInvite> decline({required String inviteId}) =>
      throw UnimplementedError();

  @override
  Future<AuthorInvite> revertDecline({required String inviteId}) =>
      throw UnimplementedError();

  @override
  Future<List<PendingAuthorInvite>> myPending() => throw UnimplementedError();
}

AuthorInvite _invite(
  String userId,
  AuthorInviteStatus status, {
  String? note,
  int hour = 0,
}) => AuthorInvite(
  id: 'I-$userId-$hour',
  beaconId: 'B1',
  inviteeId: userId,
  status: status,
  note: note,
  createdAt: _t.add(Duration(hours: hour)),
);

BeaconAuthorInvitesCubit _cubit(_Port port, FakeUiEffectPort effects) =>
    BeaconAuthorInvitesCubit(
      beaconId: 'B1',
      authorInviteCase: AuthorInviteCase(
        port,
        env: const Env(),
        logger: Logger('author-invites-test'),
      ),
      actorProfiles: buildActorProfiles(const [_ann, _bob, _cat, _dan]),
      effects: effects,
    );

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _author);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  @override
  late BeaconViewState state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(state);

  @override
  Future<void> reportPeopleSurfaceViewed() async {}
}

BeaconViewState _viewState({required String myId}) => BeaconViewState(
  beacon: Beacon(
    id: 'B1',
    title: 'Move the piano',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
  ),
  myProfile: Profile(id: myId, displayName: 'Me'),
);

Widget _app(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('ru'),
  home: Scaffold(body: child),
);

Widget _surface(
  BeaconViewState state, {
  BeaconAuthorInvitesCubit? invites,
  bool gate = true,
}) {
  final cubit = _MockBeaconViewCubit()..state = state;
  return _app(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        BlocProvider<BeaconViewCubit>.value(value: cubit),
      ],
      child: BeaconPeopleSurface(
        beaconViewCubit: cubit,
        beaconState: state,
        focusUserId: null,
        peopleTabAttentionActive: false,
        postBuddingEnabled: gate,
        authorInvitesCubit: invites,
      ),
    ),
  );
}

Finder _row(String userId) =>
    find.byKey(ValueKey('BeaconAuthorInviteRow.$userId'));

Finder _inRow(String userId, Finder finder) =>
    find.descendant(of: _row(userId), matching: finder);

void main() {
  group('parent link', () {
    testWidgets('a readable Post parent reads «Вырос из поста»', (
      tester,
    ) async {
      await tester.pumpPeopleTagsWidget(
        _app(
          const BeaconHierarchyParentLink(
            reference: BeaconParentReference(
              state: BeaconParentReferenceState.available,
              beaconId: 'Bpost',
              title: 'Who has a van?',
              isPost: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Вырос из поста'), findsOneWidget);
      expect(find.text('Who has a van?'), findsOneWidget);
    });

    testWidgets('a Request parent keeps its plain title link', (tester) async {
      await tester.pumpPeopleTagsWidget(
        _app(
          const BeaconHierarchyParentLink(
            reference: BeaconParentReference(
              state: BeaconParentReferenceState.available,
              beaconId: 'Bparent',
              title: 'Parent title',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Parent title'), findsOneWidget);
      expect(find.text('Вырос из поста'), findsNothing);
    });

    testWidgets('an unreadable parent shows the generic reference', (
      tester,
    ) async {
      await tester.pumpPeopleTagsWidget(
        _app(
          const BeaconHierarchyParentLink(
            reference: BeaconParentReference.unavailable,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await L10n.delegate.load(const Locale('ru'));

      expect(find.text(l10n.beaconParentUnavailable), findsOneWidget);
      expect(find.text('Вырос из поста'), findsNothing);
    });
  });

  group('rows', () {
    test('observers first, then non-observer invitees; helpers left out', () {
      final state = BeaconAuthorInvitesState(
        beaconId: 'B1',
        observerIds: const ['Uann', 'Ubob', 'Ucat', 'Udan'],
        invites: [
          _invite('Uann', AuthorInviteStatus.pending, note: 'van'),
          _invite('Ubob', AuthorInviteStatus.declined),
          _invite('Ucat', AuthorInviteStatus.accepted),
          _invite('Urepair', AuthorInviteStatus.pending),
        ],
      );

      final rows = state.rows(excludedUserIds: const {'Udan'});

      expect(rows.map((r) => r.userId), ['Uann', 'Ubob', 'Urepair']);
      final ann = rows[0];
      expect(
        (ann.canWithdraw, ann.canInvite, ann.invite?.note),
        (
          true,
          false,
          'van',
        ),
      );
      final bob = rows[1];
      expect(
        (bob.canWithdraw, bob.canInvite),
        (false, true),
        reason: 'a declined invite may be repeated',
      );
      final repair = rows[2];
      expect(
        (repair.canWithdraw, repair.canInvite),
        (true, false),
        reason: 'only snapshot observers can be invited',
      );
    });

    test('the latest invite of a person wins', () {
      final state = BeaconAuthorInvitesState(
        beaconId: 'B1',
        observerIds: const ['Uann'],
        invites: [
          _invite('Uann', AuthorInviteStatus.pending, hour: 3),
          _invite('Uann', AuthorInviteStatus.declined, hour: 1),
        ],
      );

      expect(state.rows().single.invite?.status, AuthorInviteStatus.pending);
    });

    test('a withdrawn or expired invite leaves a plain observer row', () {
      final state = BeaconAuthorInvitesState(
        beaconId: 'B1',
        observerIds: const ['Uann'],
        invites: [_invite('Uann', AuthorInviteStatus.withdrawn)],
      );

      final row = state.rows().single;
      expect(row.invite, isNull);
      expect(row.canInvite, isTrue);
    });
  });

  group('People tab', () {
    late _Port port;
    late FakeUiEffectPort effects;

    setUp(() {
      port = _Port()
        ..observers = const ['Uann', 'Ubob', 'Ucat']
        ..invites = [
          _invite(
            'Uann',
            AuthorInviteStatus.pending,
            note: 'У вас есть фургон',
          ),
          _invite('Ubob', AuthorInviteStatus.declined),
        ];
      effects = FakeUiEffectPort();
    });

    testWidgets('the author sees statuses, notes, withdraw and «Позвать»', (
      tester,
    ) async {
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit),
      );
      await tester.pumpAndSettle();

      expect(find.text('Кого позвать'), findsOneWidget);
      expect(_inRow('Uann', find.text('Ann')), findsOneWidget);
      expect(_inRow('Uann', find.text('приглашён(а)')), findsOneWidget);
      expect(_inRow('Uann', find.text('У вас есть фургон')), findsOneWidget);
      expect(
        _inRow('Uann', find.text('Отозвать приглашение')),
        findsOneWidget,
      );
      expect(_inRow('Uann', find.text('Позвать')), findsNothing);
      expect(_inRow('Ubob', find.text('не сможет')), findsOneWidget);
      expect(_inRow('Ubob', find.text('Позвать')), findsOneWidget);
      expect(_inRow('Ucat', find.text('Позвать')), findsOneWidget);
      expect(_inRow('Ucat', find.text('приглашён(а)')), findsNothing);
    });

    testWidgets('«Позвать» invites the observer and shows them invited', (
      tester,
    ) async {
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit),
      );
      await tester.pumpAndSettle();

      await tester.tap(_inRow('Ucat', find.text('Позвать')));
      await tester.pumpAndSettle();

      expect(port.created, ['Ucat']);
      expect(_inRow('Ucat', find.text('приглашён(а)')), findsOneWidget);
      expect(
        _inRow('Ucat', find.text('Отозвать приглашение')),
        findsOneWidget,
      );
    });

    // #734: the row turning into Withdraw was the only sign it worked.
    test('a sent «Позвать» confirms it, naming the invitee', () async {
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.invite('Ucat');

      final sent = effects.emitted
          .whereType<ShowMessage>()
          .map((e) => e.message)
          .whereType<AuthorInviteSentMessage>();
      expect(sent.map((m) => m.toRu), ['Приглашение отправлено: Cat']);
      expect(sent.single.toEn, 'Invitation sent to Cat');
    });

    test('a refused «Позвать» confirms nothing', () async {
      port.createOutcome = PostBudInviteOutcome.recipientPaused;
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.invite('Ucat');

      expect(
        effects.emitted
            .whereType<ShowMessage>()
            .map((e) => e.message)
            .whereType<AuthorInviteSentMessage>(),
        isEmpty,
      );
      expect(cubit.state.notInvited?.userId, 'Ucat');
    });

    testWidgets('a refused «Позвать» names the person in a snack', (
      tester,
    ) async {
      port.createOutcome = PostBudInviteOutcome.recipientPaused;
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit),
      );
      await tester.pumpAndSettle();

      await tester.tap(_inRow('Ucat', find.text('Позвать')));
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось позвать: Cat', findRichText: true),
        findsOneWidget,
      );
      expect(_inRow('Ucat', find.text('Позвать')), findsOneWidget);
    });

    testWidgets('withdraw turns the invite back into «Позвать»', (
      tester,
    ) async {
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit),
      );
      await tester.pumpAndSettle();

      await tester.tap(_inRow('Uann', find.text('Отозвать приглашение')));
      await tester.pumpAndSettle();

      expect(port.withdrawn, ['I-Uann-0']);
      expect(_inRow('Uann', find.text('приглашён(а)')), findsNothing);
      expect(_inRow('Uann', find.text('Позвать')), findsOneWidget);
    });

    testWidgets('a failed load shows the error and no section', (
      tester,
    ) async {
      final failing = _FailingPort();
      final cubit = BeaconAuthorInvitesCubit(
        beaconId: 'B1',
        authorInviteCase: AuthorInviteCase(
          failing,
          env: const Env(),
          logger: Logger('author-invites-test'),
        ),
        actorProfiles: buildActorProfiles(const []),
        effects: effects,
      );
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit),
      );
      await tester.pumpAndSettle();

      expect(find.text('Кого позвать'), findsNothing);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });

    testWidgets('a non-author sees no section and asks for nothing', (
      tester,
    ) async {
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'Uann'), invites: cubit),
      );
      await tester.pumpAndSettle();

      expect(find.text('Кого позвать'), findsNothing);
      expect(find.text('Позвать'), findsNothing);
      expect(port.reads, isEmpty);
    });

    testWidgets('gate off hides the section from the author', (tester) async {
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit, gate: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Кого позвать'), findsNothing);
      expect(port.reads, isEmpty);
    });

    testWidgets('an ordinary Request shows nothing to its author', (
      tester,
    ) async {
      port
        ..observers = const []
        ..invites = const [];
      final cubit = _cubit(port, effects);
      addTearDown(cubit.close);
      await tester.pumpPeopleTagsWidget(
        _surface(_viewState(myId: 'auth'), invites: cubit),
      );
      await tester.pumpAndSettle();

      expect(port.reads, isNotEmpty);
      expect(find.text('Кого позвать'), findsNothing);
    });
  });
}

final class _FailingPort extends _Port {
  @override
  Future<List<String>> budObservers({required String beaconId}) async =>
      throw StateError('offline');
}
