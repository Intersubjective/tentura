import 'package:test/test.dart';

import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

class _StubInvitationRepository implements InvitationRepository {
  _StubInvitationRepository();

  List<InvitationEntity> fetchResult = [];
  Object? fetchError;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<InvitationEntity>> fetchMine({int offset = 0, int limit = 10}) {
    final error = fetchError;
    if (error != null) {
      return Future.error(error);
    }
    return Future.value(fetchResult);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final invite = InvitationEntity(
    id: 'Iabc123',
    addresseeName: 'Bob from gym',
    createdAt: DateTime.utc(2026, 6, 12),
    updatedAt: DateTime.utc(2026, 6, 12),
  );

  group('InvitationCubit.fetch', () {
    test('failed refetch keeps the already-loaded list and count', () async {
      final repo = _StubInvitationRepository()..fetchResult = [invite];
      final cubit = InvitationCubit(invitationRepository: repo);

      await cubit.fetch();
      expect(cubit.state.invitations, hasLength(1));

      repo.fetchError = Exception('boom');
      await cubit.fetch();

      expect(
        cubit.state.invitations,
        hasLength(1),
        reason: 'a failed refetch must not wipe the visible list',
      );
      expect(cubit.state.status, isA<StateHasError>());

      await cubit.close();
    });

    test('successful clear-refetch replaces, not appends', () async {
      final repo = _StubInvitationRepository()..fetchResult = [invite];
      final cubit = InvitationCubit(invitationRepository: repo);

      await cubit.fetch();
      await cubit.fetch();

      expect(cubit.state.invitations, hasLength(1));

      await cubit.close();
    });
  });
}
