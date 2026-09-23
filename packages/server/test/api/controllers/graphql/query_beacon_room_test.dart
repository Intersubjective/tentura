import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../support/fake_beacon_hierarchy_repository.dart';
import '../../../support/fake_user_block_repository.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

String _baseTypeName(GraphQLType type) {
  var t = type;
  while (true) {
    if (t is GraphQLNonNullableType) {
      t = t.ofType;
    } else if (t is GraphQLListType) {
      t = t.ofType;
    } else {
      return t.name ?? t.toString();
    }
  }
}

void main() {
  late QueryBeaconRoom query;

  setUp(() {
    query = QueryBeaconRoom(
      beaconRoomCase: BeaconRoomCase(
        _FakeRoom(),
        _FakeItems(),
        _FakeFactCards(),
        _FakeImages(),
        _FakeTasks(),
        _FakeRemoteStorage(),
        _FakePolling(),
        _FakeUploadQuota(),
        FakeUserBlockRepository(),
        PassThroughMutatingUnitOfWork(),
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        env: Env(environment: Environment.test),
        logger: Logger('QueryBeaconRoomTest'),
      ),
    );
  });

  test(
    'QueryBeaconRoom.all exposes BeaconRoomReadWatermarks as [v2_RoomReadWatermark!]',
    () {
      final field = query.all.singleWhere(
        (f) => f.name == 'BeaconRoomReadWatermarks',
      );

      expect(field.type, isA<GraphQLListType<dynamic, dynamic>>());
      final listType = field.type as GraphQLListType<dynamic, dynamic>;
      expect(listType.ofType, isA<GraphQLNonNullableType<dynamic, dynamic>>());
      expect(_baseTypeName(listType.ofType), 'v2_RoomReadWatermark');
    },
  );
}

class _FakeRoom extends Fake implements BeaconRoomRepositoryPort {}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      true;
}
