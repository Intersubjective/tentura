import 'dart:async';

import 'package:logging/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';

import '../features/auth/auth_test_helpers.dart';
import '../features/contacts/contacts_case_test.dart';
import 'fake_person_shared_context_port.dart';
import 'fake_wake_up_port.dart';
import 'test_realtime_sync.dart';

/// One `setLike` request seen by [TrustLikeRepository].
final class TrustLikeCall {
  TrustLikeCall(this.id, this.amount);

  final String id;
  final int amount;
  final result = Completer<void>();
}

/// Like repository whose writes stay in flight until the test settles them.
final class TrustLikeRepository implements LikeRemoteRepository {
  final calls = <TrustLikeCall>[];

  /// Settle every write at once with an acknowledgement.
  bool autoAck = false;

  List<int> get amounts => [for (final call in calls) call.amount];

  void ack(int index) => calls[index].result.complete();

  void fail(int index, Object error) =>
      calls[index].result.completeError(error);

  @override
  Stream<RepositoryEvent<Likable>> get changes => const Stream.empty();

  @override
  Future<T> setLike<T extends Likable>(T entity, {required int amount}) async {
    final call = TrustLikeCall(entity.id, amount);
    calls.add(call);
    if (autoAck) {
      call.result.complete();
    }
    await call.result.future;
    return (entity as Profile).copyWith(myVote: amount) as T;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Profile repository that counts every re-read.
final class CountingProfileRepository implements ProfileRepositoryPort {
  final byId = <String, Profile>{};
  int fetchCalls = 0;

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
    return byId[id] ?? Profile(id: id);
  }

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The actual timer selected by the writer, including its R4 jitter.
final class TrustWakeUpCall {
  TrustWakeUpCall(this.delay, this.handle);
  final Duration delay;
  final WakeUpHandle handle;
}

/// Records production scheduling and advances only when a test says so.
final class TrustWakeUpPort implements WakeUpPort {
  final _delegate = FakeWakeUpPort();
  final calls = <TrustWakeUpCall>[];

  @override
  WakeUpHandle schedule(Duration delay, void Function() callback) {
    final handle = _delegate.schedule(delay, callback);
    calls.add(TrustWakeUpCall(delay, handle));
    return handle;
  }

  void elapse(Duration duration) => _delegate.elapse(duration);
}

/// R4 is jittered exponential backoff: the first base is 1 s, then 2 s.
/// Constellation uses equal jitter (half the base through the full base).
/// Verify the selected delay, then let callers assert its exact boundary.
Duration expectR4RetryScheduled(
  TrustWakeUpPort wakeUp,
  int schedulesBeforeFailure, {
  required int attempt,
}) {
  final baseMilliseconds = 1000 * (1 << (attempt - 1));
  // A writer may re-arm its notice for the same absolute deadline. Identify
  // the retry timer by its backoff window rather than counting every timer.
  final retryTimers = wakeUp.calls
      .skip(schedulesBeforeFailure)
      .where((call) => call.delay <= Duration(milliseconds: baseMilliseconds))
      .toList();
  expect(
    retryTimers,
    hasLength(1),
    reason: 'one retry timer in the R4 backoff window',
  );
  final delay = retryTimers.single.delay;
  expect(
    delay.inMilliseconds,
    inInclusiveRange(baseMilliseconds ~/ 2 + 1, baseMilliseconds),
    reason:
        'R4 attempt $attempt must use its exponential base with equal jitter',
  );
  expect(retryTimers.single.handle.isActive, isTrue);
  return delay;
}

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);
  @override
  final Stream<String> currentAccountChanges;
}

/// One real account-owned writer shared by every panel cubit in the fixture.
final class GraphTrustWriteFixture {
  GraphTrustWriteFixture({
    ProfileRepositoryPort? profileRepository,
    LikeRemoteRepository? likeRepository,
  }) {
    this.profileRepository = profileRepository ?? profiles;
    writeRepository = likeRepository ?? likes;
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    final authLocal = StreamingAuthLocal();
    final authCase = buildTestAuthCase(authLocal, EmptyAuthRemote());
    final contactStore = ContactNameStore();
    final contacts = ContactsCase(
      FakeContactsRepository(),
      authCase,
      contactStore,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    profileViewCase = ProfileViewCase(
      this.profileRepository,
      writeRepository,
      _FakeCapabilityRepository(),
      contacts,
      realtime.case_,
      FakePersonSharedContextPort(),
      env: const Env(),
      logger: Logger('test'),
    );
    trustWriteCase = GraphTrustWriteCase(
      writeRepository,
      wakeUp,
      _AccountPort(account.stream),
      env: const Env(),
      logger: Logger('trust-writer-test'),
    );
    _disposeCollaborators.addAll([
      contacts.dispose,
      realtime.port.dispose,
      contactStore.dispose,
      authLocal.dispose,
    ]);
  }

  final likes = TrustLikeRepository();
  final profiles = CountingProfileRepository();
  final wakeUp = TrustWakeUpPort();
  final account = BehaviorSubject<String>.seeded('Ume');
  late final ProfileRepositoryPort profileRepository;
  late final LikeRemoteRepository writeRepository;
  late final ProfileViewCase profileViewCase;
  late final TestRealtimeSyncPort realtimePort;
  late final GraphTrustWriteCase trustWriteCase;
  final _disposeCollaborators = <Future<void> Function()>[];
  final _cubits = <GraphPersonContextCubit>[];

  GraphPersonContextCubit get contextCubit => _cubits.single;

  GraphPersonContextCubit createCubit({
    ProfileViewCase? profileViewCase,
    String viewerId = 'Ume',
    void Function(Profile)? onProfilePatched,
  }) {
    final cubit = GraphPersonContextCubit(
      profileViewCase: profileViewCase ?? this.profileViewCase,
      trustWriteCase: trustWriteCase,
      viewerId: viewerId,
      onProfilePatched: onProfilePatched,
    );
    _cubits.add(cubit);
    return cubit;
  }

  Future<void> dispose() async {
    for (final cubit in _cubits) {
      if (!cubit.isClosed) await cubit.close();
    }
    await trustWriteCase.dispose();
    await account.close();
    for (final dispose in _disposeCollaborators) {
      await dispose();
    }
  }
}
