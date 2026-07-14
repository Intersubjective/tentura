import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/contacts/data/repository/contacts_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';

import '../auth/auth_test_helpers.dart';
import '../../support/test_realtime_sync.dart';

void main() {
  group('ContactNameStore', () {
    late ContactNameStore store;

    setUp(() => store = ContactNameStore());

    tearDown(() => store.dispose());

    test('replaceAll replaces the full map and emits', () async {
      final events = <void>[];
      final sub = store.changes.listen(events.add);

      store.replaceAll({'u1': 'Alice', 'u2': 'Bob'});

      expect(store.nameOf('u1'), 'Alice');
      expect(store.nameOf('u2'), 'Bob');
      expect(store.all, {'u1': 'Alice', 'u2': 'Bob'});
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('remove emits only when an entry existed', () async {
      store.replaceAll({'u1': 'Alice'});
      final events = <void>[];
      final sub = store.changes.listen(events.add);

      store.remove('missing');
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      store.remove('u1');
      await Future<void>.delayed(Duration.zero);
      expect(store.nameOf('u1'), isNull);
      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('clear emits only when the map was non-empty', () async {
      store.set('u1', 'Alice');
      final events = <void>[];
      final sub = store.changes.listen(events.add);

      store.clear();
      await Future<void>.delayed(Duration.zero);

      expect(store.all, isEmpty);
      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('ContactsCase', () {
    late StreamingAuthLocal authLocal;
    late FakeContactsRepository repository;
    late ContactNameStore store;
    late ContactsCase case_;
    late TestRealtimeSyncPort realtimePort;
    late RealtimeSyncCase realtimeSyncCase;
    late Future<void> Function(String accountId) switchAccount;

    setUp(() {
      authLocal = StreamingAuthLocal();
      repository = FakeContactsRepository();
      store = ContactNameStore();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      realtimeSyncCase = realtime.case_;
      case_ = ContactsCase(
        repository,
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
        store,
        realtimeSyncCase,
        env: const Env(),
        logger: Logger('test'),
      );
      switchAccount = (accountId) async {
        if (accountId.isEmpty) {
          authLocal.emit(accountId);
          await Future<void>.delayed(Duration.zero);
          return;
        }
        final syncReady = repository.nextSync();
        authLocal.emit(accountId);
        await syncReady;
        await Future<void>.delayed(Duration.zero);
      };
    });

    tearDown(() async {
      await case_.dispose();
      await realtimeSyncCase.dispose();
      await realtimePort.dispose();
      await store.dispose();
      await authLocal.dispose();
    });

    test('sign-out clears ContactNameStore', () async {
      store.set('u1', 'Alice');
      await switchAccount('acc-1');

      await switchAccount('');

      expect(store.all, isEmpty);
      expect(case_.nameOf('u1'), isNull);
    });

    test('account switch loads cache then merges server names', () async {
      repository.cachedByAccount['acc-1'] = {'u1': 'Cached'};
      repository.fetchMineResult = {'u1': 'Server', 'u2': 'Friend'};

      await switchAccount('acc-1');

      expect(repository.lastGetCachedAccountId, 'acc-1');
      expect(case_.nameOf('u1'), 'Server');
      expect(case_.nameOf('u2'), 'Friend');
      expect(repository.lastReplaceCache?.accountId, 'acc-1');
      expect(
        repository.lastReplaceCache?.names,
        {'u1': 'Server', 'u2': 'Friend'},
      );
    });

    test('refresh failure keeps cached names in store', () async {
      repository.cachedByAccount['acc-1'] = {'u1': 'Offline'};
      repository.fetchMineError = StateError('network');

      await switchAccount('acc-1');

      expect(case_.nameOf('u1'), 'Offline');
    });

    test('ignores stale fetch when account switches mid-refresh', () async {
      final staleFetch = Completer<void>();
      final accBFetch = Completer<void>();
      var fetchCount = 0;
      repository.fetchMineHandler = () async {
        fetchCount++;
        if (fetchCount == 1) {
          await staleFetch.future;
          return {'u1': 'A-server'};
        }
        await accBFetch.future;
        return {'u2': 'B-server'};
      };
      repository.cachedByAccount['acc-a'] = {'u1': 'A-cache'};
      repository.cachedByAccount['acc-b'] = {'u2': 'B-cache'};

      final accACache = repository.nextCacheLoad();
      authLocal.emit('acc-a');
      await accACache;

      final accBCache = repository.nextCacheLoad();
      authLocal.emit('acc-b');
      await accBCache;
      await Future<void>.delayed(Duration.zero);
      expect(case_.nameOf('u2'), 'B-cache');

      accBFetch.complete();
      final accBSync = repository.nextSync();
      await accBSync;
      await Future<void>.delayed(Duration.zero);
      expect(case_.nameOf('u2'), 'B-server');

      staleFetch.complete();
      await repository.nextSync();
      await Future<void>.delayed(Duration.zero);

      expect(case_.nameOf('u1'), isNull);
      expect(case_.nameOf('u2'), 'B-server');
    });

    test('rename trims contact name and updates store', () async {
      await switchAccount('acc-1');

      await case_.rename(subjectId: 'u-bob', contactName: '  Bob  ');

      expect(case_.nameOf('u-bob'), 'Bob');
      expect(
        repository.lastSetContact,
        (subjectId: 'u-bob', contactName: 'Bob'),
      );
      expect(
        repository.lastPutCached,
        (
          accountId: 'acc-1',
          subjectId: 'u-bob',
          contactName: 'Bob',
        ),
      );
    });

    test('reset removes contact from store and cache', () async {
      await switchAccount('acc-1');
      store.set('u-bob', 'Bob');

      await case_.reset(subjectId: 'u-bob');

      expect(case_.nameOf('u-bob'), isNull);
      expect(repository.lastDeleteContactSubjectId, 'u-bob');
      expect(
        repository.lastRemoveCached,
        (accountId: 'acc-1', subjectId: 'u-bob'),
      );
    });

    test('changes stream emits on rename', () async {
      await switchAccount('acc-1');

      final events = <void>[];
      final sub = case_.changes.listen(events.add);

      await case_.rename(subjectId: 'u-bob', contactName: 'Bob');
      await Future<void>.delayed(Duration.zero);

      expect(events, isNotEmpty);
      await sub.cancel();
    });

    test('manual refresh replaces store from server', () async {
      await switchAccount('acc-1');

      repository.fetchMineResult = {'u1': 'Updated'};
      final syncReady = repository.nextSync();
      await case_.refresh();
      await syncReady;
      await Future<void>.delayed(Duration.zero);

      expect(case_.nameOf('u1'), 'Updated');
    });

    test('remote contact change refreshes the full private map', () async {
      await switchAccount('acc-1');
      repository.fetchMineResult = {'u2': 'Renamed elsewhere'};

      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.contact,
          aggregateId: 'u2',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(store.all, {'u2': 'Renamed elsewhere'});
      expect(repository.lastReplaceCache?.accountId, 'acc-1');
    });

    test('catch-up refreshes contacts after a missed event', () async {
      await switchAccount('acc-1');
      repository.fetchMineResult = {'u3': 'Caught up'};

      realtimePort.emitCatchUp();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(store.all, {'u3': 'Caught up'});
    });

    test('contact invalidation burst coalesces into one refresh', () async {
      await switchAccount('acc-1');
      final callsBefore = repository.fetchMineCalls;
      repository.fetchMineResult = {'u4': 'Once'};
      const change = RealtimeEntityChange(
        kind: RealtimeEntityKind.contact,
        aggregateId: 'u4',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      );

      realtimePort
        ..emitChange(change)
        ..emitChange(change)
        ..emitChange(change);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(repository.fetchMineCalls, callsBefore + 1);
      expect(store.all, {'u4': 'Once'});
    });
  });
}

class StreamingAuthLocal implements AuthLocalRepositoryPort {
  StreamingAuthLocal([this._current = '']);

  String _current;
  final _controller = StreamController<String>.broadcast();

  void emit(String accountId) {
    _current = accountId;
    _controller.add(accountId);
  }

  @override
  Stream<String> currentAccountChanges() => Stream.multi((multi) {
    multi.add(_current);
    final sub = _controller.stream.listen(
      multi.add,
      onError: multi.addError,
      onDone: multi.close,
    );
    multi.onCancel = sub.cancel;
  });

  @override
  Future<void> dispose() => _controller.close();

  @override
  Future<String> getCurrentAccountId() async => _current;

  @override
  Future<void> setCurrentAccountId(String? id) async {
    _current = id ?? '';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeContactsRepository implements ContactsRepository {
  Map<String, Map<String, String>> cachedByAccount = {};
  Map<String, String> fetchMineResult = {};
  Object? fetchMineError;
  Future<Map<String, String>> Function()? fetchMineHandler;
  int fetchMineCalls = 0;

  final _cacheGates = <Completer<void>>[];
  final _syncGates = <Completer<void>>[];

  String? lastGetCachedAccountId;
  ({String accountId, Map<String, String> names})? lastReplaceCache;
  ({String subjectId, String contactName})? lastSetContact;
  ({String accountId, String subjectId, String contactName})? lastPutCached;
  String? lastDeleteContactSubjectId;
  ({String accountId, String subjectId})? lastRemoveCached;

  Future<void> nextCacheLoad() {
    final gate = Completer<void>();
    _cacheGates.add(gate);
    return gate.future;
  }

  Future<void> nextSync() {
    final gate = Completer<void>();
    _syncGates.add(gate);
    return gate.future;
  }

  void _completeGate(List<Completer<void>> gates) {
    if (gates.isEmpty) return;
    gates.removeAt(0).complete();
  }

  @override
  Future<Map<String, String>> getCached({required String accountId}) async {
    lastGetCachedAccountId = accountId;
    final result = Map<String, String>.from(
      cachedByAccount[accountId] ?? const {},
    );
    scheduleMicrotask(() => _completeGate(_cacheGates));
    return result;
  }

  @override
  Future<Map<String, String>> fetchMine() async {
    fetchMineCalls++;
    try {
      if (fetchMineHandler != null) {
        return await fetchMineHandler!();
      }
      if (fetchMineError != null) {
        throw fetchMineError!;
      }
      return Map.from(fetchMineResult);
    } finally {
      _completeGate(_syncGates);
    }
  }

  @override
  Future<void> replaceCache({
    required String accountId,
    required Map<String, String> names,
  }) async {
    lastReplaceCache = (accountId: accountId, names: Map.from(names));
    cachedByAccount[accountId] = Map.from(names);
  }

  @override
  Future<void> setContact({
    required String subjectId,
    required String contactName,
  }) async {
    lastSetContact = (subjectId: subjectId, contactName: contactName);
  }

  @override
  Future<void> deleteContact({required String subjectId}) async {
    lastDeleteContactSubjectId = subjectId;
  }

  @override
  Future<void> putCached({
    required String accountId,
    required String subjectId,
    required String contactName,
  }) async {
    lastPutCached = (
      accountId: accountId,
      subjectId: subjectId,
      contactName: contactName,
    );
    cachedByAccount.putIfAbsent(accountId, () => {})[subjectId] = contactName;
  }

  @override
  Future<void> removeCached({
    required String accountId,
    required String subjectId,
  }) async {
    lastRemoveCached = (accountId: accountId, subjectId: subjectId);
    cachedByAccount[accountId]?.remove(subjectId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
