import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/item_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/threads_list.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';

import 'fake_coordination_item_case.dart';

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream<ThreadsState>.value(_state);
}

class _ToggleThreadsCubit extends Mock implements ThreadsCubit {
  _ToggleThreadsCubit(ThreadsState initial) {
    _state = initial;
    _controller = StreamController<ThreadsState>.broadcast();
    _controller.add(initial);
  }

  late ThreadsState _state;
  late final StreamController<ThreadsState> _controller;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => _controller.stream;

  @override
  void setActiveForMeOnly(bool value) {
    _state = _state.copyWith(activeForMeOnly: value);
    _controller.add(_state);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _SpyBeaconViewCubit extends Mock implements BeaconViewCubit {
  @override
  BeaconViewState get state => _state;

  final BeaconViewState _state;

  _SpyBeaconViewCubit(this._state);

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);
}

const _kBeaconId = 'B-threads-list';
const _kAuthorId = 'author-1';
const _kOtherId = 'other-1';
const _kMyId = 'author-1';
final _kNow = DateTime.utc(2026, 8, 14, 12, 30);

CoordinationItem _item({
  required String id,
  CoordinationItemKind kind = CoordinationItemKind.ask,
  CoordinationItemStatus status = CoordinationItemStatus.open,
  bool published = true,
  String creatorId = _kAuthorId,
  String? targetPersonId = _kOtherId,
  int unreadCount = 0,
  String title = 'Item body',
}) =>
    CoordinationItem(
      id: id,
      beaconId: _kBeaconId,
      kind: kind,
      status: status,
      creatorId: creatorId,
      createdAt: _kNow,
      updatedAt: _kNow,
      published: published,
      targetPersonId: targetPersonId,
      title: title,
      unreadCount: unreadCount,
    );

RequestThread _generalThread({
  int unreadCount = 0,
  ThreadMessagePreview? preview,
  String? authorId,
}) =>
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      unreadCount: unreadCount,
      messageCount: 3,
      lastMessageAt: _kNow.subtract(const Duration(minutes: 5)),
      lastMessageAuthorId: authorId ?? _kOtherId,
      lastMessagePreview: preview ??
          const ThreadMessagePreview(
            kind: ThreadMessagePreviewKind.text,
            excerpt: 'General hello',
          ),
    );

RequestThread _semanticThread({
  required CoordinationItem item,
  int unreadCount = 0,
  ThreadMessagePreview? preview,
}) =>
    RequestThread(
      threadId: item.id,
      kind: switch (item.kind) {
        CoordinationItemKind.ask => RequestThreadKind.ask,
        CoordinationItemKind.promise => RequestThreadKind.promise,
        CoordinationItemKind.blocker => RequestThreadKind.blocker,
        CoordinationItemKind.plan => RequestThreadKind.ask,
      },
      unreadCount: unreadCount,
      messageCount: item.messageCount,
      item: item,
      lastMessageAt: _kNow.subtract(const Duration(hours: 1)),
      lastMessageAuthorId: item.creatorId,
      lastMessagePreview: preview,
    );

BeaconViewState _beaconViewState({
  List<BeaconParticipant> participants = const [],
}) =>
    BeaconViewState(
      beacon: Beacon(
        id: _kBeaconId,
        title: 'Test request',
        author: const Profile(id: _kAuthorId, displayName: 'Author'),
        createdAt: _kNow,
        updatedAt: _kNow,
      ),
      myProfile: const Profile(id: _kMyId, displayName: 'Author'),
      roomParticipants: participants,
      roomParticipantsLoaded: true,
    );

Widget _wrapThreadsList({
  required ThreadsCubit threadsCubit,
  required BeaconViewState beaconState,
  required void Function(RequestThread thread) onOpenThread,
  VoidCallback? onSwitchToPeopleTab,
  Size size = const Size(400, 900),
}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<ThreadsCubit>.value(value: threadsCubit),
            BlocProvider<BeaconViewCubit>.value(
              value: _SpyBeaconViewCubit(beaconState),
            ),
          ],
          child: ThreadsList(
            beaconState: beaconState,
            onOpenThread: onOpenThread,
            onSwitchToPeopleTab: onSwitchToPeopleTab,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders General row with title and preview', (tester) async {
    final threadsState = ThreadsState(
      threads: [_generalThread()],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    final opened = <RequestThread>[];
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: opened.add,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.threadGeneralTitle), findsOneWidget);
    expect(find.textContaining('General hello'), findsOneWidget);
    expect(
      find.byKey(TestIds.key(TestIds.requestThread(RequestThread.generalId))),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(TestIds.key(TestIds.requestThread(RequestThread.generalId))),
    );
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(opened.single.isGeneral, isTrue);
  });

  testWidgets('General face pile tap does not open thread', (tester) async {
    final threadsState = ThreadsState(
      threads: [_generalThread()],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    final opened = <RequestThread>[];
    var peopleTabTaps = 0;
    final beaconState = _beaconViewState().copyWith(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: _kOtherId, displayName: 'Helper'),
          message: 'help',
          createdAt: _kNow,
          updatedAt: _kNow,
        ),
      ],
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: beaconState,
        onOpenThread: opened.add,
        onSwitchToPeopleTab: () => peopleTabTaps++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BeaconInvolvedPeopleFacePile), findsOneWidget);
    await tester.tap(find.byType(BeaconInvolvedPeopleFacePile));
    await tester.pumpAndSettle();
    expect(peopleTabTaps, 1);
    expect(opened, isEmpty);
  });

  testWidgets('groups active, closed, and drafts in order', (tester) async {
    final active = _item(id: 'active-1', title: 'Active unique body');
    final closed = _item(
      id: 'closed-1',
      status: CoordinationItemStatus.resolved,
      title: 'Closed unique body',
    );
    final draft = _item(
      id: 'draft-1',
      published: false,
      title: 'Draft unique body',
    );
    final threadsState = ThreadsState(
      threads: [
        _generalThread(),
        _semanticThread(item: active),
        _semanticThread(item: closed),
        _semanticThread(item: draft),
      ],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.threadGeneralTitle), findsOneWidget);
    expect(find.text('Active unique body'), findsOneWidget);
    expect(find.text('Closed unique body'), findsNothing);
    expect(find.text('Draft unique body'), findsNothing);

    await tester.tap(find.text(l10n.threadClosedFoldTitle(1)));
    await tester.pumpAndSettle();
    expect(find.text('Closed unique body'), findsOneWidget);

    await tester.tap(find.text(l10n.threadDraftsFoldTitle(1)));
    await tester.pumpAndSettle();
    expect(find.text('Draft unique body'), findsOneWidget);
  });

  testWidgets('unread badge on active semantic row, not on closed', (tester) async {
    final active = _item(id: 'active-u', unreadCount: 2);
    final closed = _item(
      id: 'closed-u',
      status: CoordinationItemStatus.resolved,
      unreadCount: 4,
    );
    final threadsState = ThreadsState(
      threads: [
        _generalThread(unreadCount: 1),
        _semanticThread(item: active, unreadCount: 2),
        _semanticThread(item: closed, unreadCount: 4),
      ],
      resolvedUnreadByThreadId: {
        'active-u': 2,
        RequestThread.generalId: 1,
        'closed-u': 4,
      },
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('draft tap opens composer sheet not thread callback', (tester) async {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<CoordinationItemCase>()) {
      await getIt.unregister<CoordinationItemCase>();
    }
    getIt.registerSingleton<CoordinationItemCase>(
      const FakeCoordinationItemCaseForRoom(),
    );
    addTearDown(() async {
      if (getIt.isRegistered<CoordinationItemCase>()) {
        await getIt.unregister<CoordinationItemCase>();
      }
    });

    final draft = _item(
      id: 'draft-tap',
      published: false,
      title: 'Draft tap body',
    );
    final threadsState = ThreadsState(
      threads: [_generalThread(), _semanticThread(item: draft)],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    final opened = <RequestThread>[];
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: opened.add,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.threadDraftsFoldTitle(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft tap body'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(
      find.byKey(TestIds.key(TestIds.coordinationComposerTitle)),
      findsOneWidget,
    );
  });

  testWidgets('preview families render localized labels', (tester) async {
    final previews = <ThreadMessagePreview>[
      const ThreadMessagePreview(
        kind: ThreadMessagePreviewKind.planUpdated,
      ),
      const ThreadMessagePreview(
        kind: ThreadMessagePreviewKind.poll,
        pollTitle: 'Lunch poll',
      ),
      const ThreadMessagePreview(
        kind: ThreadMessagePreviewKind.needInfo,
      ),
    ];
    final threads = <RequestThread>[
      _generalThread(preview: previews[0]),
      _semanticThread(
        item: _item(id: 'p1'),
        preview: previews[1],
      ),
      _semanticThread(
        item: _item(id: 'p2'),
        preview: previews[2],
      ),
    ];
    final threadsState = ThreadsState(
      threads: threads,
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.textContaining(l10n.beaconRoomSemanticPlan), findsOneWidget);
    expect(find.textContaining('Lunch poll'), findsOneWidget);
    expect(
      find.textContaining(l10n.beaconRoomSemanticNeedInfo),
      findsOneWidget,
    );
  });

  testWidgets('empty active fold shows threadNoActiveItems', (tester) async {
    final threadsState = ThreadsState(
      threads: [_generalThread()],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.threadNoActiveItems), findsOneWidget);
  });

  testWidgets('activeForMeOnly filter hides non-involved threads', (tester) async {
    final mine = _item(
      id: 'mine',
      creatorId: _kMyId,
      targetPersonId: _kOtherId,
      title: 'Mine body',
    );
    final other = _item(
      id: 'other',
      creatorId: _kOtherId,
      targetPersonId: 'third',
      title: 'Other body',
    );
    final threadsState = ThreadsState(
      threads: [
        _generalThread(),
        _semanticThread(item: mine),
        _semanticThread(item: other),
      ],
      myUserId: _kMyId,
      activeForMeOnly: true,
      status: const StateIsSuccess(),
    );
    final cubit = _ToggleThreadsCubit(threadsState);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: cubit,
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mine body'), findsOneWidget);
    expect(find.text('Other body'), findsNothing);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Mine body'), findsOneWidget);
    expect(find.text('Other body'), findsOneWidget);
  });

  testWidgets('overflow menu reachable via secondary tap', (tester) async {
    final active = _item(id: 'menu-item', creatorId: _kMyId);
    final threadsState = ThreadsState(
      threads: [_generalThread(), _semanticThread(item: active)],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final menuFinder = find.byKey(
      TestIds.key(TestIds.coordinationItemMenu('menu-item')),
    );
    expect(menuFinder, findsOneWidget);

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.coordinationBlockerActionResolve), findsOneWidget);
  });

  testWidgets('never renders raw user id in preview author', (tester) async {
    const rawId = 'Uraw000000001';
    final threadsState = ThreadsState(
      threads: [
        _generalThread(
          authorId: rawId,
          preview: const ThreadMessagePreview(
            kind: ThreadMessagePreviewKind.text,
            excerpt: 'secret preview',
          ),
        ),
      ],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenThread: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(rawId), findsNothing);
    expect(find.textContaining('secret preview'), findsOneWidget);
  });
}
