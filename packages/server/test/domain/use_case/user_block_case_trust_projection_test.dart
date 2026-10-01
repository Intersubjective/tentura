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
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/recording_commitment_repository.dart';

/// B1 step 3: block and unblock use cases call
/// `TrustLedgerPort.project([(blocker, blocked)])` inside the unit of work,
/// after the block row changed. The case takes the ledger as the named
/// `trustLedger` argument.
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
  }) async {}

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

final class _Inbox extends Fake implements InboxRepositoryPort {}

final class _Evidence extends Fake implements CapabilityEvidencePort {}

void main() {
  UserBlockCase build(_Ledger ledger) => UserBlockCase(
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
    trustLedger: ledger,
    env: Env(environment: Environment.test),
    logger: Logger('UserBlockCaseTrustProjectionTest'),
  );

  setUp(_log.clear);

  test('block projects (blocker, blocked) inside the unit of work', () async {
    final ledger = _Ledger();

    await build(ledger).block(
      blockerId: _blocker,
      blockedId: _blocked,
      cascadeMode: 0,
    );

    expect(ledger.projected, [
      [(_blocker, _blocked)],
    ]);
    expect(_log.indexOf('project'), greaterThan(_log.indexOf('block')));
    expect(_log.indexOf('project'), lessThan(_log.indexOf('uow:end')));
  });

  test(
    'unblock projects (blocker, blocked) after the row is removed',
    () async {
      final ledger = _Ledger();

      await build(ledger).unblock(blockerId: _blocker, blockedId: _blocked);

      expect(ledger.projected, [
        [(_blocker, _blocked)],
      ]);
      expect(_log.indexOf('project'), greaterThan(_log.indexOf('unblock')));
      expect(_log.indexOf('project'), lessThan(_log.indexOf('uow:end')));
    },
  );
}
