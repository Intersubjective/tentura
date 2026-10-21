import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

/// Server-side invitation lists for #502. A fetch reads the server state at
/// the moment it is sent; [gateNextFetch] holds the answer back, so a
/// pushed (silent) refetch can be kept in flight while the user edits, and
/// [releaseGate] lets that older answer land late, after the edit.
class _ServerInvitationRepository implements InvitationRepository {
  final pending = <InvitationEntity>[];
  final accepted = <InvitationEntity>[];

  int fetchCount = 0;
  Completer<void>? _gate;
  Completer<void>? _held;
  final _heldAnswered = Completer<void>();
  final _changes = StreamController<void>.broadcast();

  void gateNextFetch() => _gate = Completer<void>();

  /// Completes the fetch held by [gateNextFetch] and waits until its (older)
  /// answer has been returned to the cubit.
  Future<void> releaseGate() async {
    final held = _held;
    if (held == null) fail('no fetch is held by the gate');
    held.complete();
    await _heldAnswered.future;
  }

  @override
  Stream<void> get changes => _changes.stream;

  // Like the real repository: a local mutation tells every cubit afterwards.
  void _notifyChanges() => scheduleMicrotask(() {
    if (!_changes.isClosed) _changes.add(null);
  });

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 5,
    int acceptedOffset = 0,
    int acceptedLimit = 5,
  }) async {
    fetchCount++;
    final snapshot = (
      pending: List<InvitationEntity>.of(pending),
      accepted: List<InvitationEntity>.of(accepted),
      pendingCount: pending.length,
    );
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      _held = gate;
      await gate.future;
      // Answer first, then signal, so the cubit sees the old answer before
      // the test goes on.
      scheduleMicrotask(_heldAnswered.complete);
    }
    return snapshot;
  }

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) async {
    final created = _pending('Inew');
    pending.add(created);
    _notifyChanges();
    return created;
  }

  @override
  Future<void> deleteById(String id) async {
    pending.removeWhere((e) => e.id == id);
    _notifyChanges();
  }

  Future<void> close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

InvitationEntity _pending(String id) => InvitationEntity(
  id: id,
  addresseeName: 'Person $id',
  createdAt: DateTime.utc(2026, 10, 14),
  updatedAt: DateTime.utc(2026, 10, 14),
);

InvitationEntity _accepted(String id) => InvitationEntity(
  id: id,
  invitedId: 'U$id',
  invitedName: 'Person $id',
  inviteOrigin: 'new_account',
  addresseeName: 'Person $id',
  createdAt: DateTime.utc(2026, 10, 14),
  updatedAt: DateTime.utc(2026, 10, 14),
  acceptedAt: DateTime.utc(2026, 10, 14, 1),
);

/// Waits up to 2 s of fake time (see [_fakeTest]) for [condition].
Future<void> _waitFor(bool Function() condition) async {
  for (var waited = 0; !condition(); waited += 10) {
    if (waited >= 2000) fail('condition not reached within 2 s');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Lets every debounced refetch run to completion.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 600));

/// Runs [body] in fake time: the cubit's refresh debounce and the helpers'
/// delays fire as fake time is advanced, never on the wall clock.
///
/// Fake time is advanced between real event-loop turns, because a cancelled
/// stream subscription answers with a root-zone future that fake time alone
/// never completes (cubit.close() would hang under a plain fakeAsync).
void _fakeTest(String description, Future<void> Function() body) {
  test(description, () async {
    final fake = FakeAsync();
    var done = false;
    Object? error;
    StackTrace? stack;
    fake.run((_) {
      unawaited(
        body().then<void>(
          (_) => done = true,
          onError: (Object e, StackTrace s) {
            error = e;
            stack = s;
          },
        ),
      );
    });
    for (var i = 0; !done && error == null && i < 1000; i++) {
      await Future<void>.delayed(Duration.zero);
      fake.run((async) => async.elapse(const Duration(milliseconds: 10)));
    }
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    if (!done) fail('the test did not finish within 10 s of fake time');
  });
}

void main() {
  group('#502 a local edit during a pushed refetch is not lost', () {
    late _ServerInvitationRepository repo;
    late StreamController<void> serverChanges;
    late InvitationCubit cubit;

    Future<void> start() async {
      repo = _ServerInvitationRepository()
        ..pending.addAll([_pending('Ia'), _pending('Ib'), _pending('Ix')]);
      serverChanges = StreamController<void>.broadcast();
      cubit = InvitationCubit(
        invitationRepository: repo,
        effects: FakeUiEffectPort(),
        serverChanges: serverChanges.stream,
      );
      await cubit.fetch();
      expect(cubit.state.pendingCount, 3);
    }

    Future<void> stop() async {
      await cubit.close();
      await serverChanges.close();
      await repo.close();
    }

    // Set-up and tear-down run inside the test's fake-time zone, so the
    // cubit's timers are fake too.
    void fakeTest(String description, Future<void> Function() body) =>
        _fakeTest(description, () async {
          await start();
          try {
            await body();
          } finally {
            await stop();
          }
        });

    /// Invite Ix is accepted elsewhere: the server moves it to Accepted and
    /// pushes; the pushed refetch is held in flight.
    Future<void> acceptElsewhereAndHoldRefetch() async {
      repo.pending.removeWhere((e) => e.id == 'Ix');
      repo.accepted.add(_accepted('Ix'));
      repo.gateNextFetch();
      final before = repo.fetchCount;
      serverChanges.add(null);
      await _waitFor(() => repo.fetchCount == before + 1);
    }

    fakeTest(
      'a deleted invite does not come back from an older answer',
      () async {
        await acceptElsewhereAndHoldRefetch();

        await cubit.deleteInvitationById('Ia');
        // The repository change after the delete arrives while the pushed
        // refetch is still in flight.
        await _settle();
        expect(cubit.state.pendingInvitations.map((e) => e.id).toSet(), {'Ib'});

        // The older answer (taken before the delete: Ia, Ib; count 2) lands
        // late, after the delete. It must be ignored.
        await repo.releaseGate();
        await _settle();

        expect(
          cubit.state.pendingInvitations.map((e) => e.id).toSet(),
          {'Ib'},
          reason: 'the deleted invite must not reappear under Pending',
        );
        expect(
          cubit.state.pendingCount,
          1,
          reason:
              'the Invitations (N) badge follows the server after the delete',
        );
        // Negative guard: the accept that caused the push still shows.
        expect(
          cubit.state.acceptedInvitations.map((e) => e.id),
          ['Ix'],
          reason: 'the accepted invite must move to Accepted',
        );
        expect(repo.fetchCount, lessThan(8), reason: 'no refetch loop');
      },
    );

    fakeTest('a new invite does not vanish under an older answer', () async {
      await acceptElsewhereAndHoldRefetch();

      final created = await cubit.createInvitation(addresseeName: '');
      expect(created, isNotNull);
      await _settle();
      expect(
        cubit.state.pendingInvitations.map((e) => e.id).toSet(),
        {'Ia', 'Ib', 'Inew'},
      );

      // The older answer (taken before the create: Ia, Ib; count 2) lands
      // late. It must be ignored.
      await repo.releaseGate();
      await _settle();

      expect(
        cubit.state.pendingInvitations.map((e) => e.id).toSet(),
        {'Ia', 'Ib', 'Inew'},
        reason: 'the invite just created must stay under Pending',
      );
      expect(cubit.state.pendingCount, 3);
      expect(cubit.state.acceptedInvitations.map((e) => e.id), ['Ix']);
      expect(repo.fetchCount, lessThan(8), reason: 'no refetch loop');
    });

    fakeTest(
      'pull to refresh during a pushed refetch is not dropped',
      () async {
        await acceptElsewhereAndHoldRefetch();

        // Another invite is accepted after the pushed refetch was sent; no
        // second push arrives, the user pulls to refresh instead.
        repo.pending.removeWhere((e) => e.id == 'Ib');
        repo.accepted.add(_accepted('Ib'));
        await cubit.fetch();
        await _settle();
        expect(
          cubit.state.acceptedInvitations.map((e) => e.id).toSet(),
          {'Ix', 'Ib'},
          reason: 'the refresh asked for after the push must still run',
        );

        // The pushed answer (taken before the refresh: accepted Ix only,
        // count 2) lands late. The refresh result must stand.
        await repo.releaseGate();
        await _settle();

        expect(
          cubit.state.acceptedInvitations.map((e) => e.id).toSet(),
          {'Ix', 'Ib'},
          reason: 'the older pushed answer must not overwrite the refresh',
        );
        expect(cubit.state.pendingCount, 1);
        expect(repo.fetchCount, lessThan(8), reason: 'no refetch loop');
      },
    );
  });
}
