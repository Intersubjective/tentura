import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

final class _FakeAuthCubit implements AuthCubit {
  _FakeAuthCubit(String accountId)
    : _state = AuthState(
        updatedAt: DateTime.utc(2026),
        currentAccountId: accountId,
      );

  final AuthState _state;
  final _states = StreamController<AuthState>.broadcast();

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _states.stream;

  Future<void> disposeFake() => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSettingsRepository implements SettingsRepositoryPort {
  int? inboxLastSeen = 10;
  int? myWorkLastSeen = 20;
  final inboxWrites = <int>[];
  final myWorkWrites = <int>[];
  final hydrated = Completer<void>();
  var _readCount = 0;

  @override
  Future<int?> getNewStuffInboxLastSeenMs(String accountId) async {
    _recordRead();
    return inboxLastSeen;
  }

  @override
  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId) async {
    _recordRead();
    return myWorkLastSeen;
  }

  void _recordRead() {
    if (++_readCount == 2) hydrated.complete();
  }

  @override
  Future<void> setNewStuffInboxLastSeenMs(String accountId, int value) async {
    inboxLastSeen = value;
    inboxWrites.add(value);
  }

  @override
  Future<void> setNewStuffMyWorkLastSeenMs(String accountId, int value) async {
    myWorkLastSeen = value;
    myWorkWrites.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('keeps Inbox and My Work dots local to their Drift cursors', () async {
    final settings = _FakeSettingsRepository();
    final auth = _FakeAuthCubit('U1');
    final cubit = NewStuffCubit(settings, auth);
    await settings.hydrated.future;
    await Future<void>.delayed(Duration.zero);

    cubit
      ..reportInboxActivity(11)
      ..reportMyWorkActivity(21);

    expect(cubit.hasNewInboxDot, isTrue);

    cubit.setActiveHomeTab(HomeTab.inbox);
    expect(cubit.hasNewInboxDot, isFalse);
    expect(cubit.hasNewMyWorkDot, isTrue);

    await cubit.markInboxTabSeen();
    expect(settings.inboxWrites, [11]);
    expect(cubit.hasNewInboxDot, isFalse);

    await cubit.close();
    unawaited(auth.disposeFake());
  });

  test('retains Inbox row highlight semantics', () async {
    final settings = _FakeSettingsRepository();
    final auth = _FakeAuthCubit('U1');
    final cubit = NewStuffCubit(settings, auth);
    await settings.hydrated.future;
    await Future<void>.delayed(Duration.zero);

    expect(
      cubit.inboxRowHighlight(
        latestForwardAt: DateTime.fromMillisecondsSinceEpoch(11),
        forwardCount: 1,
        beaconActivityEpochMs: 11,
      ),
      InboxRowHighlightKind.newForwardActivity,
    );
    expect(
      cubit.inboxRowHighlight(
        latestForwardAt: DateTime.fromMillisecondsSinceEpoch(10),
        forwardCount: 1,
        beaconActivityEpochMs: 11,
      ),
      InboxRowHighlightKind.updatedBeaconOnly,
    );

    await cubit.close();
    unawaited(auth.disposeFake());
  });
}
