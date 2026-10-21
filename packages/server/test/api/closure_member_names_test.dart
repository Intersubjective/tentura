// #489 (round 7): Close & sum up and "if colleagues stay silent" showed a
// helper the author removed as a raw id ("U784390f7cdc3 removed"). The
// closure state must carry every member's name (and avatar when there is
// one), the removed and the voluntarily departed included, for the author
// and for the colleagues alike. Names come with the closure member rows
// (`ClosureMemberRow.displayName` / `avatarId`, joined from `user` by
// `ClosureRepository.members`) and travel through `ClosureMemberView` and
// `QueryClosure` unchanged.

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_closure.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/env.dart';

import '../support/beacon_lifecycle_effects_test_support.dart';
import '../support/fake_beacon_hierarchy_repository.dart';

const _beaconId = 'Bclnamesbeac01';
const _authorId = 'Uclnamesauth01';
const _voterId = 'Uclnamesvote01';
const _leaverId = 'Uclnamesleav01';
const _removedId = 'U784390f7cdc3';

const _names = {
  _voterId: 'Vera Voter',
  _leaverId: 'Lev Leaver',
  _removedId: 'Rita Removed',
};

const _avatars = {
  _voterId: '0b6a3c3e-1111-4c4c-8d8d-000000000001',
  _removedId: '0b6a3c3e-1111-4c4c-8d8d-000000000003',
};

void main() {
  late GraphQL graph;

  setUp(() => graph = _graph());

  Future<Map<String, Map<String, dynamic>>> membersFor(String viewer) async {
    final out = await graph.parseAndExecute(
      '{ closureState(beaconId: "$_beaconId") '
      '{ role members { id displayName avatarId departure } } }',
      globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
    );
    final s = (out! as Map)['closureState'] as Map;
    return {
      for (final m in (s['members'] as List).cast<Map<dynamic, dynamic>>())
        m['id'] as String: Map<String, dynamic>.from(m),
    };
  }

  test('author: a removed helper comes with a name, not only an id', () async {
    final members = await membersFor(_authorId);

    expect(members.keys, containsAll(<String>[_removedId, _leaverId]));
    expect(members[_removedId]!['departure'], 'removed');
    expect(members[_removedId]!['displayName'], 'Rita Removed');
    expect(members[_removedId]!['avatarId'], _avatars[_removedId]);
  });

  test('author: every member carries the name from its row', () async {
    final members = await membersFor(_authorId);

    for (final MapEntry(key: id, value: name) in _names.entries) {
      expect(members[id]!['displayName'], name, reason: 'name of $id');
    }
    // No avatar on the row stays no avatar (never the id or a placeholder).
    expect(members[_leaverId]!['avatarId'], isNull);
  });

  test('colleague: departed members are named for a voter too', () async {
    final members = await membersFor(_voterId);

    expect(members[_removedId]!['displayName'], 'Rita Removed');
    expect(members[_leaverId]!['displayName'], 'Lev Leaver');
    expect(members[_voterId]!['displayName'], 'Vera Voter');
    // Departure detail stays author-only (unchanged by the fix).
    expect(members[_removedId]!['departure'], isNull);
  });
}

GraphQL _graph() {
  final c = ClosureCase(
    unitOfWork: _PassThroughUow(),
    closureRepository: _Repo(),
    beaconRepository: _Beacons(),
    commitmentRepository: _Commitments(),
    helpOfferRepository: _NoHelpOffers(),
    hierarchyRepository: FakeBeaconHierarchyRepository(),
    lifecycleEffects: buildLifecycleEffectsCase(),
    attentionSystemSettlement: _NoSettlement(),
    receipts: _NoReceipts(),
    finalizer: _NoFinalizer(),
    env: Env(environment: Environment.test),
    logger: Logger('ClosureMemberNamesTest'),
  );
  return GraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', null)
        ..fields.addAll(QueryClosure(closureCase: c).all),
    ),
    customTypes: customTypes,
  );
}

final _t0 = DateTime.utc(2026, 10);

final class _Repo implements ClosureRepositoryPort {
  ClosureEpoch get _epoch => ClosureEpoch(
    beaconId: _beaconId,
    epoch: 1,
    status: ClosureEpochStatus.evaluating,
    openedAt: _t0,
    closesAt: _t0.add(const Duration(days: 7)),
    extensionsUsed: 0,
  );

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) async =>
      beaconId == _beaconId ? _epoch : null;

  @override
  Future<ClosureEpoch?> latestEpoch(String beaconId) async =>
      beaconId == _beaconId ? _epoch : null;

  @override
  Future<List<ClosureMemberRow>> members({
    required String beaconId,
    required int epoch,
  }) async => [
    ClosureMemberRow(
      userId: _voterId,
      activeAtOpen: true,
      displayName: _names[_voterId],
      avatarId: _avatars[_voterId],
    ),
    ClosureMemberRow(
      userId: _leaverId,
      activeAtOpen: true,
      departure: Departure.voluntary,
      displayName: _names[_leaverId],
    ),
    ClosureMemberRow(
      userId: _removedId,
      activeAtOpen: true,
      departure: Departure.removed,
      displayName: _names[_removedId],
      avatarId: _avatars[_removedId],
    ),
  ];

  @override
  Future<List<ClosureOutcomeRow>> outcomes(String beaconId) async => const [];

  @override
  Future<Map<String, int>> split(String beaconId) async => const {};

  @override
  Future<List<ClosureSupportRow>> supports({
    required String beaconId,
    required ClosureSupportVersion version,
  }) async => const [];

  @override
  Future<List<ClosureCommitRow>> commits(String beaconId) async => const [];

  @override
  Future<List<ClosureMarkRow>> marks(String beaconId) async => const [];

  @override
  Future<String?> story(String beaconId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Beacons implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    if (beaconId != _beaconId) throw IdNotFoundException(id: beaconId);
    return BeaconEntity(
      id: _beaconId,
      title: 't',
      author: const UserEntity(id: _authorId),
      createdAt: _t0,
      updatedAt: _t0,
      status: BeaconStatus.reviewOpen,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Commitments implements CommitmentRepositoryPort {
  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(
    String beaconId,
  ) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoHelpOffers implements HelpOfferRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PassThroughUow implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoSettlement implements AttentionSystemSettlementPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoReceipts implements ClosureReceiptsPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoFinalizer implements ClosureFinalizerPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
