import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_discussion_cubit.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_discussion_state.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../beacon_room/fake_coordination_item_case.dart';

class _FakeCoordinationItemCaseForDiscussion extends FakeCoordinationItemCaseForRoom {
  List<CoordinationItemMessage> messages = [];
  bool markItemSeenCalled = false;
  DateTime? lastSeenAtAfterMark;
  Completer<void>? listMessagesCompleter;

  @override
  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  }) async {
    final gate = listMessagesCompleter;
    if (gate != null) {
      listMessagesCompleter = null;
      await gate.future;
    }
    return messages;
  }

  @override
  Future<void> markItemSeenIfAllowed(String itemId) async {
    markItemSeenCalled = true;
    lastSeenAtAfterMark = DateTime.timestamp();
  }

  @override
  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String body,
  }) async {
    final msg = CoordinationItemMessage(
      id: 'm-sent',
      itemId: itemId,
      beaconId: _kBeaconId,
      senderId: _kMyUserId,
      body: body,
      createdAt: DateTime.timestamp(),
    );
    messages = [...messages, msg];
    return msg;
  }
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(String userId) : _userId = userId;
  final String _userId;

  @override
  ProfileState get state =>
      ProfileState(profile: Profile(id: _userId, title: 'T'));

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

const _kBeaconId = 'b-test';
const _kItemId = 'item-test';
const _kMyUserId = 'me-test';

final _kAnchorTime = DateTime.utc(2026, 1, 1, 12);

CoordinationItemMessage _itemMsg(
  String id,
  DateTime createdAt, {
  String senderId = 'other',
}) =>
    CoordinationItemMessage(
      id: id,
      itemId: _kItemId,
      beaconId: _kBeaconId,
      senderId: senderId,
      body: '',
      createdAt: createdAt,
    );

CoordinationItem _testItem({DateTime? lastSeenAt}) => CoordinationItem(
      id: _kItemId,
      beaconId: _kBeaconId,
      kind: CoordinationItemKind.ask,
      status: CoordinationItemStatus.accepted,
      creatorId: _kMyUserId,
      createdAt: _kAnchorTime,
      updatedAt: _kAnchorTime,
      lastSeenAt: lastSeenAt,
    );

void _registerProfileCubit(String userId) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ProfileCubit>()) {
    // ignore: discarded_futures
    getIt.unregister<ProfileCubit>();
  }
  getIt.registerSingleton<ProfileCubit>(_MockProfileCubit(userId));
  addTearDown(() {
    if (getIt.isRegistered<ProfileCubit>()) {
      // ignore: discarded_futures
      getIt.unregister<ProfileCubit>();
    }
  });
}

Future<ItemDiscussionState> _awaitFetch(ItemDiscussionCubit cubit) =>
    cubit.stream.firstWhere((s) => s.status is! StateIsLoading);

void main() {
  group('ItemDiscussionCubit unread anchor', () {
    test('fetchMessages() snapshots anchor from item.lastSeenAt', () async {
      _registerProfileCubit(_kMyUserId);

      final fakeCase = _FakeCoordinationItemCaseForDiscussion()
        ..messages = [
          _itemMsg('old', _kAnchorTime.subtract(const Duration(hours: 1))),
          _itemMsg('new', _kAnchorTime.add(const Duration(hours: 1))),
        ];

      final cubit = ItemDiscussionCubit(
        item: _testItem(lastSeenAt: _kAnchorTime),
        coordinationItemCase: fakeCase,
        listenToInvalidation: false,
      );
      addTearDown(cubit.close);

      unawaited(cubit.fetchMessages());
      final s = await _awaitFetch(cubit);

      expect(s.unreadAnchorAt, equals(_kAnchorTime));
      expect(s.unreadCount, 1);
      expect(s.firstUnreadMessageId, 'new');
      expect(s.pendingMarkSeen, isTrue);
    });

    test('markSeenNowIfNeeded() does not overwrite unreadAnchorAt', () async {
      _registerProfileCubit(_kMyUserId);

      final fakeCase = _FakeCoordinationItemCaseForDiscussion()
        ..messages = [
          _itemMsg('new', _kAnchorTime.add(const Duration(hours: 1))),
        ];

      final cubit = ItemDiscussionCubit(
        item: _testItem(lastSeenAt: _kAnchorTime),
        coordinationItemCase: fakeCase,
        listenToInvalidation: false,
      );
      addTearDown(cubit.close);

      unawaited(cubit.fetchMessages());
      await _awaitFetch(cubit);
      final anchorBefore = cubit.state.unreadAnchorAt;

      await cubit.markSeenNowIfNeeded();

      expect(cubit.state.unreadAnchorAt, equals(anchorBefore));
      expect(cubit.state.pendingMarkSeen, isFalse);
      expect(fakeCase.markItemSeenCalled, isTrue);
    });

    test('markSeenNowIfNeeded() is blocked while fetch is in progress', () async {
      _registerProfileCubit(_kMyUserId);

      final fakeCase = _FakeCoordinationItemCaseForDiscussion();

      final cubit = ItemDiscussionCubit(
        item: _testItem(lastSeenAt: _kAnchorTime),
        coordinationItemCase: fakeCase,
        listenToInvalidation: false,
      );
      addTearDown(cubit.close);

      unawaited(cubit.fetchMessages());
      await _awaitFetch(cubit);

      final gate = Completer<void>();
      fakeCase
        ..listMessagesCompleter = gate
        ..markItemSeenCalled = false;

      unawaited(cubit.fetchMessages());
      await cubit.markSeenNowIfNeeded();

      expect(fakeCase.markItemSeenCalled, isFalse);

      gate.complete();
      await _awaitFetch(cubit);
    });

    test('sendMessage() advances anchor so thread is fully seen', () async {
      _registerProfileCubit(_kMyUserId);

      final msgTime = _kAnchorTime.add(const Duration(hours: 1));
      final fakeCase = _FakeCoordinationItemCaseForDiscussion()
        ..messages = [
          _itemMsg('m1', msgTime),
        ];

      final cubit = ItemDiscussionCubit(
        item: _testItem(lastSeenAt: _kAnchorTime),
        coordinationItemCase: fakeCase,
        listenToInvalidation: false,
      );
      addTearDown(cubit.close);

      unawaited(cubit.fetchMessages());
      await _awaitFetch(cubit);
      expect(cubit.state.unreadCount, 1);

      await cubit.sendMessage('reply');

      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.firstUnreadMessageId, isNull);
      expect(fakeCase.markItemSeenCalled, isTrue);
    });
  });
}
