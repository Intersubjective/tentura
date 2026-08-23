import 'package:test/test.dart';

import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

typedef _FetchCall = ({
  int pendingOffset,
  int pendingLimit,
  int acceptedOffset,
  int acceptedLimit,
});

class _StubInvitationRepository implements InvitationRepository {
  _StubInvitationRepository();

  List<InvitationEntity> pendingResult = [];
  List<InvitationEntity> acceptedResult = [];
  int pendingCountResult = 0;
  Object? fetchError;

  final calls = <_FetchCall>[];

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 10,
    int acceptedOffset = 0,
    int acceptedLimit = 10,
  }) async {
    calls.add((
      pendingOffset: pendingOffset,
      pendingLimit: pendingLimit,
      acceptedOffset: acceptedOffset,
      acceptedLimit: acceptedLimit,
    ));
    final error = fetchError;
    if (error != null) {
      return Future.error(error);
    }
    // Simulate offset-based paging over the configured full results.
    List<InvitationEntity> page(List<InvitationEntity> all, int offset, int limit) =>
        offset >= all.length ? const [] : all.skip(offset).take(limit).toList();
    return (
      pending: page(pendingResult, pendingOffset, pendingLimit),
      accepted: page(acceptedResult, acceptedOffset, acceptedLimit),
      pendingCount: pendingCountResult,
    );
  }

  int _nextId = 0;
  final deletedIds = <String>[];

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) async => _pending('Icreated${_nextId++}');

  @override
  Future<void> deleteById(String id) async {
    deletedIds.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

InvitationEntity _pending(String id, {DateTime? createdAt}) => InvitationEntity(
  id: id,
  addresseeName: 'Person $id',
  createdAt: createdAt ?? DateTime.utc(2026, 6, 12),
  updatedAt: createdAt ?? DateTime.utc(2026, 6, 12),
);

InvitationEntity _accepted(String id, {DateTime? acceptedAt}) => InvitationEntity(
  id: id,
  invitedId: 'U$id',
  invitedName: 'Person $id',
  inviteOrigin: 'existing_account',
  acceptedAt: acceptedAt ?? DateTime.utc(2026, 6, 13),
  createdAt: DateTime.utc(2026, 6, 12),
  updatedAt: DateTime.utc(2026, 6, 13),
);

void main() {
  final invite = _pending('Iabc123');

  group('InvitationCubit.fetch', () {
    test('failed refetch keeps the already-loaded list and count', () async {
      final repo = _StubInvitationRepository()
        ..pendingResult = [invite]
        ..pendingCountResult = 1;
      final effects = FakeUiEffectPort();
      final cubit = InvitationCubit(
        invitationRepository: repo,
        effects: effects,
      );

      await cubit.fetch();
      expect(cubit.state.pendingInvitations, hasLength(1));

      repo.fetchError = Exception('boom');
      await cubit.fetch();

      expect(
        cubit.state.pendingInvitations,
        hasLength(1),
        reason: 'a failed refetch must not wipe the visible list',
      );
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);

      await cubit.close();
    });

    test('successful clear-refetch replaces, not appends', () async {
      final repo = _StubInvitationRepository()..pendingResult = [invite];
      final cubit = InvitationCubit(
        invitationRepository: repo,
        effects: FakeUiEffectPort(),
      );

      await cubit.fetch();
      await cubit.fetch();

      expect(cubit.state.pendingInvitations, hasLength(1));

      await cubit.close();
    });

    test('pendingCount reflects the true aggregate, not the loaded list length', () async {
      final repo = _StubInvitationRepository()
        ..pendingResult = [invite] // only one page loaded
        ..pendingCountResult = 42; // but many more exist server-side
      final cubit = InvitationCubit(
        invitationRepository: repo,
        effects: FakeUiEffectPort(),
      );

      await cubit.fetch();

      expect(cubit.state.pendingInvitations, hasLength(1));
      expect(cubit.state.pendingCount, 42);

      await cubit.close();
    });

    test('loads both segments independently in one fetch', () async {
      final repo = _StubInvitationRepository()
        ..pendingResult = [_pending('Ip1')]
        ..acceptedResult = [_accepted('Ia1')]
        ..pendingCountResult = 1;
      final cubit = InvitationCubit(
        invitationRepository: repo,
        effects: FakeUiEffectPort(),
      );

      await cubit.fetch();

      expect(cubit.state.pendingInvitations.map((e) => e.id), ['Ip1']);
      expect(cubit.state.acceptedInvitations.map((e) => e.id), ['Ia1']);

      await cubit.close();
    });
  });

  group('InvitationCubit segment pagination independence', () {
    test(
      'fetchMorePending paginates only Pending, leaving Accepted untouched',
      () async {
        final repo = _StubInvitationRepository()
          ..pendingResult = List.generate(3, (i) => _pending('Ip$i'))
          ..acceptedResult = [_accepted('Ia0')]
          ..pendingCountResult = 3;
        final cubit = InvitationCubit(
          invitationRepository: repo,
          effects: FakeUiEffectPort(),
        );

        await cubit.fetch();
        final loadedPending = cubit.state.pendingInvitations.length;
        final acceptedBefore = cubit.state.acceptedInvitations;

        await cubit.fetchMorePending();

        final call = repo.calls.last;
        expect(
          call.pendingOffset,
          loadedPending,
          reason: 'must page Pending forward from what is already loaded',
        );
        expect(
          call.acceptedLimit,
          0,
          reason: 'must not re-fetch Accepted while paging Pending',
        );
        expect(
          cubit.state.acceptedInvitations,
          same(acceptedBefore),
          reason: 'Accepted must be untouched by a Pending-only page load',
        );

        await cubit.close();
      },
    );

    test(
      'fetchMoreAccepted paginates only Accepted, leaving Pending untouched',
      () async {
        final repo = _StubInvitationRepository()
          ..pendingResult = [_pending('Ip0')]
          ..acceptedResult = List.generate(3, (i) => _accepted('Ia$i'))
          ..pendingCountResult = 1;
        final cubit = InvitationCubit(
          invitationRepository: repo,
          effects: FakeUiEffectPort(),
        );

        await cubit.fetch();
        final loadedAccepted = cubit.state.acceptedInvitations.length;
        final pendingBefore = cubit.state.pendingInvitations;

        await cubit.fetchMoreAccepted();

        final call = repo.calls.last;
        expect(
          call.acceptedOffset,
          loadedAccepted,
          reason: 'must page Accepted forward from what is already loaded',
        );
        expect(
          call.pendingLimit,
          0,
          reason: 'must not re-fetch Pending while paging Accepted',
        );
        expect(
          cubit.state.pendingInvitations,
          same(pendingBefore),
          reason: 'Pending must be untouched by an Accepted-only page load',
        );

        await cubit.close();
      },
    );

    test(
      'a page containing rows of only one kind does not starve the other '
      "segment's ability to keep paginating (each segment tracks its own "
      'hasReachedMax independently)',
      () async {
        final repo = _StubInvitationRepository()
          ..pendingResult = List.generate(5, (i) => _pending('Ip$i'))
          ..acceptedResult = const []
          ..pendingCountResult = 5;
        final cubit = InvitationCubit(
          invitationRepository: repo,
          effects: FakeUiEffectPort(),
        );

        await cubit.fetch();
        expect(cubit.state.acceptedHasReachedMax, isTrue);
        expect(cubit.state.pendingHasReachedMax, isFalse);

        // Even though this fetch's page was Pending-only, Accepted's
        // hasReachedMax must not have been forced false again.
        await cubit.fetchMorePending();
        expect(cubit.state.acceptedHasReachedMax, isTrue);

        await cubit.close();
      },
    );
  });

  group('InvitationCubit.createInvitation / deleteInvitationById', () {
    test(
      'createInvitation appends to Pending and increments pendingCount '
      'without a full refetch',
      () async {
        final repo = _StubInvitationRepository()
          ..pendingResult = [invite]
          ..pendingCountResult = 1;
        final cubit = InvitationCubit(
          invitationRepository: repo,
          effects: FakeUiEffectPort(),
        );
        await cubit.fetch();
        expect(cubit.state.pendingCount, 1);

        final callsBefore = repo.calls.length;
        await cubit.createInvitation(addresseeName: 'New person');

        expect(cubit.state.pendingInvitations, hasLength(2));
        expect(cubit.state.pendingCount, 2);
        expect(
          repo.calls.length,
          callsBefore,
          reason: 'creating must not trigger an extra fetchMine round trip',
        );

        await cubit.close();
      },
    );

    test(
      'deleteInvitationById removes from Pending and decrements '
      'pendingCount without a full refetch',
      () async {
        final repo = _StubInvitationRepository()
          ..pendingResult = [invite]
          ..pendingCountResult = 1;
        final cubit = InvitationCubit(
          invitationRepository: repo,
          effects: FakeUiEffectPort(),
        );
        await cubit.fetch();

        final callsBefore = repo.calls.length;
        await cubit.deleteInvitationById(invite.id);

        expect(cubit.state.pendingInvitations, isEmpty);
        expect(cubit.state.pendingCount, 0);
        expect(repo.deletedIds, [invite.id]);
        expect(
          repo.calls.length,
          callsBefore,
          reason: 'deleting must not trigger an extra fetchMine round trip',
        );

        await cubit.close();
      },
    );

    test('pendingCount never goes negative on an unexpected double delete', () async {
      final repo = _StubInvitationRepository()
        ..pendingResult = [invite]
        ..pendingCountResult = 0; // already 0, e.g. after external change
      final cubit = InvitationCubit(
        invitationRepository: repo,
        effects: FakeUiEffectPort(),
      );
      await cubit.fetch();

      await cubit.deleteInvitationById(invite.id);

      expect(cubit.state.pendingCount, 0);

      await cubit.close();
    });
  });
}
