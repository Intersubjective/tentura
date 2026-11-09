import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/data/repository/mock/witness_window_repository_mock.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/commitment_gates_harness.dart';

/// Block and unblock drop both users' cached witness windows inside the unit
/// of work: after the block row (and, for a block, the withdrawal) changed and
/// before the trust ledger projects the pair. Blocker first, then blocked.
const _blocker = 'U-blocker';
const _blocked = 'U-blocked';

final _log = <String>[];

final class _UoW extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    _log.add('uow:begin');
    final r = await action();
    _log.add('uow:end');
    return r;
  }
}

final class _Blocks extends Fake implements UserBlockRepositoryPort {
  @override
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  }) async => 0;

  @override
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async => _log.add('block');

  @override
  Future<void> applyWithdrawal({
    required String blockerId,
    required String blockedId,
  }) async => _log.add('applyWithdrawal');

  @override
  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) async => _log.add('unblock');
}

final class _Ledger extends Fake implements TrustLedgerPort {
  final projected = <List<(String, String)>>[];

  @override
  Future<void> project(List<(String, String)> pairs) async {
    _log.add('project');
    projected.add(pairs);
  }
}

final class _Users extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id);
}

final class _HelpOffers extends Fake implements HelpOfferRepositoryPort {
  @override
  Future<List<Never>> fetchByUserId(String userId) async => [];
}

final class _Edges extends Fake implements ForwardEdgeRepositoryPort {
  @override
  Future<List<Never>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) async => [];
}

final class _Contacts extends Fake implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async => false;
}

final class _Beacons extends Fake implements BeaconRepositoryPort {}

final class _Inbox extends Fake implements InboxRepositoryPort {
  @override
  Future<List<String>> fetchRejectedUserIdsByBeacon(String beaconId) async =>
      const [];
}

final class _Evidence extends Fake implements CapabilityEvidencePort {}

final class _WitnessWindow extends WitnessWindowRepositoryMock {
  @override
  Future<void> invalidateFor({required String userId}) async =>
      _log.add('invalidate:$userId');
}

void main() {
  UserBlockCase build({_WitnessWindow? witnessWindow}) => UserBlockCase(
    _UoW(),
    _Blocks(),
    _HelpOffers(),
    _Edges(),
    _Contacts(),
    _Users(),
    _Beacons(),
    RecordingCommitmentRepository(),
    _Inbox(),
    _Evidence(),
    FakeBeaconHierarchyRepository(),
    roomRepository: RecordingRoomAccessRepository(),
    trustLedger: _Ledger(),
    witnessWindow: witnessWindow,
    env: Env(environment: Environment.test),
    logger: Logger('UserBlockCaseWitnessWindowTest'),
  );

  setUp(_log.clear);

  test('block invalidates blocker then blocked, before projection', () async {
    await build(witnessWindow: _WitnessWindow()).block(
      blockerId: _blocker,
      blockedId: _blocked,
      cascadeMode: 0,
    );

    expect(_log, [
      'uow:begin',
      'block',
      'applyWithdrawal',
      'invalidate:$_blocker',
      'invalidate:$_blocked',
      'project',
      'uow:end',
    ]);
  });

  test('unblock invalidates blocker then blocked, before projection', () async {
    await build(witnessWindow: _WitnessWindow()).unblock(
      blockerId: _blocker,
      blockedId: _blocked,
    );

    expect(_log, [
      'uow:begin',
      'unblock',
      'invalidate:$_blocker',
      'invalidate:$_blocked',
      'project',
      'uow:end',
    ]);
  });

  test('without a witness window block and unblock still run', () async {
    final case_ = build();
    await case_.block(blockerId: _blocker, blockedId: _blocked, cascadeMode: 0);
    await case_.unblock(blockerId: _blocker, blockedId: _blocked);

    expect(_log.where((e) => e.startsWith('invalidate:')), isEmpty);
    expect(_log.where((e) => e == 'project'), hasLength(2));
  });
}
