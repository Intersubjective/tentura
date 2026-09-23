import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/coordination_room_navigation.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_navigation_scope.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';

CoordinationItem _askItem() => CoordinationItem(
  id: 'item-ask',
  beaconId: 'beacon1',
  kind: CoordinationItemKind.ask,
  status: CoordinationItemStatus.open,
  creatorId: 'user1',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  linkedMessageId: 'msg-anchor',
);

class _TrackingRouter extends Mock implements StackRouter {
  final List<String> pushedRouteNames = [];
  final List<String> replacedRouteNames = [];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushedRouteNames.add(route.routeName);
    return null;
  }

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    replacedRouteNames.add(route.routeName);
    return null;
  }
}

class _ScrollTrackingRoomCubit extends Mock implements RoomCubit {
  _ScrollTrackingRoomCubit()
      : _state = RoomState(beaconId: 'beacon1'),
        closeCompleter = Completer<void>();

  final RoomState _state;
  final Completer<void> closeCompleter;
  bool _isClosed = false;

  int prepareThreadScrollCallCount = 0;
  String? lastMessageId;
  String? lastCoordinationItemId;
  int reloadMessagesCallCount = 0;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream.value(_state);

  @override
  bool get isClosed => _isClosed;

  @override
  void prepareThreadScroll({
    String? messageId,
    String? coordinationItemId,
  }) {
    prepareThreadScrollCallCount++;
    lastMessageId = messageId;
    lastCoordinationItemId = coordinationItemId;
  }

  @override
  Future<void> reloadMessages({bool silent = false}) async {
    reloadMessagesCallCount++;
  }

  @override
  Future<void> close() async {
    await closeCompleter.future;
    _isClosed = true;
  }
}

ThreadHostCubit _hostWithRoom(_ScrollTrackingRoomCubit room) {
  final host = ThreadHostCubit(
    beaconId: 'beacon1',
    roomCubitFactory: ({
      required String beaconId,
      String? threadItemId,
      DateTime? initialUnreadAnchorAt,
    }) =>
        room,
  );
  return host;
}

Future<void> _openHost(ThreadHostCubit host) async {
  await host.select(
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
    ),
  );
}

Widget _scopeHarness({
  required bool isRoomPresented,
  required ThreadHostCubit host,
  required BeaconRoomLease lease,
  required Future<void> Function({
    String? messageId,
    String? coordinationItemId,
  }) onOpenGeneralAnchor,
  required _TrackingRouter router,
  required Widget child,
}) {
  return StackRouterScope(
    controller: router,
    stateHash: 0,
    child: MaterialApp(
      home: BlocProvider<ThreadHostCubit>.value(
        value: host,
        child: BeaconRoomNavigationScope(
          isRoomPresented: isRoomPresented,
          roomLease: lease,
          openGeneralAnchor: onOpenGeneralAnchor,
          child: Builder(builder: (context) => child),
        ),
      ),
    ),
  );
}

void main() {
  group('isBeaconRoomPresented', () {
    test('split pane mounted counts as presented', () {
      expect(
        isBeaconRoomPresented(
          isSplit: true,
          selectedSurface: BeaconSurface.now,
        ),
        isTrue,
      );
    });

    test('CHAT tab selected counts as presented', () {
      expect(
        isBeaconRoomPresented(
          isSplit: false,
          selectedSurface: BeaconSurface.room,
        ),
        isTrue,
      );
    });

    test('NOW tab without split is not presented', () {
      expect(
        isBeaconRoomPresented(
          isSplit: false,
          selectedSurface: BeaconSurface.now,
        ),
        isFalse,
      );
    });
  });

  group('openCoordinationItemFromRoom', () {
    testWidgets('when ROOM is presented scrolls in place without routing', (
      tester,
    ) async {
      final router = _TrackingRouter();
      final room = _ScrollTrackingRoomCubit();
      final host = _hostWithRoom(room);
      await _openHost(host);
      final general = RequestThread(
        threadId: RequestThread.generalId,
        kind: RequestThreadKind.general,
      );
      final lease = BeaconRoomLease(host: host);
      await lease.acquire(Object(), general);

      late BuildContext tapContext;
      var openAnchorCalls = 0;

      await tester.pumpWidget(
        _scopeHarness(
          router: router,
          host: host,
          lease: lease,
          isRoomPresented: true,
          onOpenGeneralAnchor: ({messageId, coordinationItemId}) async {
            openAnchorCalls++;
          },
          child: Builder(
            builder: (context) {
              tapContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await openCoordinationItemFromRoom(tapContext, item: _askItem());

      expect(openAnchorCalls, 0);
      expect(router.pushedRouteNames, isEmpty);
      expect(router.replacedRouteNames, isEmpty);
      expect(room.prepareThreadScrollCallCount, 1);
      expect(room.lastMessageId, 'msg-anchor');
      expect(room.lastCoordinationItemId, 'item-ask');
      expect(room.reloadMessagesCallCount, 1);

      lease.release(Object());
      room.closeCompleter.complete();
      await host.close();
    });

    testWidgets('from NOW selects ROOM via scope without routing', (
      tester,
    ) async {
      final router = _TrackingRouter();
      final room = _ScrollTrackingRoomCubit();
      final host = _hostWithRoom(room);
      final lease = BeaconRoomLease(host: host);

      late BuildContext tapContext;
      String? openedMessageId;
      String? openedItemId;

      await tester.pumpWidget(
        _scopeHarness(
          router: router,
          host: host,
          lease: lease,
          isRoomPresented: false,
          onOpenGeneralAnchor: ({messageId, coordinationItemId}) async {
            openedMessageId = messageId;
            openedItemId = coordinationItemId;
          },
          child: Builder(
            builder: (context) {
              tapContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await openCoordinationItemFromRoom(tapContext, item: _askItem());

      expect(openedMessageId, 'msg-anchor');
      expect(openedItemId, 'item-ask');
      expect(router.pushedRouteNames, isEmpty);
      expect(router.replacedRouteNames, isEmpty);
      expect(room.prepareThreadScrollCallCount, 0);

      await host.close();
    });

    testWidgets('plan items always scroll in place', (tester) async {
      final room = _ScrollTrackingRoomCubit();
      final host = _hostWithRoom(room);
      await _openHost(host);

      final plan = CoordinationItem(
        id: 'plan1',
        beaconId: 'beacon1',
        kind: CoordinationItemKind.plan,
        status: CoordinationItemStatus.open,
        creatorId: 'user1',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        linkedMessageId: 'plan-msg',
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ThreadHostCubit>.value(
            value: host,
            child: Builder(
              key: key,
              builder: (context) => const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await openCoordinationItemFromRoom(
        key.currentContext!,
        item: plan,
        roomCubit: room,
      );

      expect(room.prepareThreadScrollCallCount, 1);
      expect(room.lastMessageId, 'plan-msg');
      expect(room.lastCoordinationItemId, 'plan1');

      room.closeCompleter.complete();
      await host.close();
    });
  });
}
