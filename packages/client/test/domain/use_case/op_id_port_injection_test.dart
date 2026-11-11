import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';

import '../../features/beacon_create/fake_beacon_ports.dart';
import '../../features/beacon_create/post_bud_fakes.dart';
import 'fake_beacon_hierarchy_ports.dart';

final class _CountingOpIds implements OpIdPort {
  int calls = 0;

  @override
  String newOpId() => 'op-${++calls}';
}

void main() {
  group('domain cases mint operation ids through OpIdPort', () {
    test(
      'BeaconHierarchyCase stores the injected id for a new child',
      () async {
        final opIds = _CountingOpIds();
        final store = InMemoryBeaconChildCommandStore();
        final write = FakeBeaconWritePort();
        final sut = buildBeaconHierarchyCaseForTest(
          FakeBeaconHierarchyRepositoryPort(),
          createCase: BeaconCreateCase(write, FakeBeaconImagePort()),
          beacons: write,
          commandStore: store,
          opIds: opIds,
        );
        const context = BeaconCreationContextChild(parentBeaconId: 'parent-1');

        final session = await sut.openComposer(creationContext: context);
        final again = await sut.openComposer(creationContext: context);

        expect(session.clientCommandId, 'op-1');
        expect(again.clientCommandId, 'op-1');
        expect(await store.read(context), 'op-1');
        expect(opIds.calls, 1);
      },
    );

    test('PostBudCase returns a fresh injected id per session', () {
      final opIds = _CountingOpIds();
      final sut = PostBudCase(
        FakePostBudPort(),
        FakeBudProfiles(),
        opIds,
        env: const Env(),
        logger: Logger('op-id-port-injection-test'),
      );

      expect(sut.newClientCommandId(), 'op-1');
      expect(sut.newClientCommandId(), 'op-2');
    });

    test('production OpIdService still mints uuid v4 strings', () {
      final id = OpIdService().newOpId();

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });
}
