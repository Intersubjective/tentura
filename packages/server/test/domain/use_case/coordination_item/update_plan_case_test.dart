import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_plan_case.dart';
import 'package:tentura_server/env.dart';

class _StubBeacons extends Fake implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      throw StateError('should not reach beacon lookup');
}

class _StubRoom extends Fake implements BeaconRoomRepository {}

class _StubItems extends Fake implements CoordinationItemRepositoryPort {}

void main() {
  late UpdatePlanCase sut;

  setUp(() {
    sut = UpdatePlanCase(
      _StubBeacons(),
      _StubItems(),
      _StubRoom(),
      _NoopRoomPush(),
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('rejects plan text longer than kBeaconRoomCurrentLineMaxLength', () async {
    final long = 'x' * (kBeaconRoomCurrentLineMaxLength + 1);
    await expectLater(
      () => sut.call(
        userId: 'Uuser00000001',
        beaconId: 'Bbbbbbbbbbbbb',
        title: long,
      ),
      throwsA(
        isA<BeaconCreateException>().having(
          (e) => e.description,
          'description',
          contains('$kBeaconRoomCurrentLineMaxLength'),
        ),
      ),
    );
  });
}

class _NoopRoomPush extends BeaconRoomPushService {
  _NoopRoomPush() : super(_NoopNotificationPort());
}

class _NoopNotificationPort extends Fake implements BeaconNotificationPort {
  @override
  Future<void> enqueue(BeaconNotificationIntent intent) async {}
}
