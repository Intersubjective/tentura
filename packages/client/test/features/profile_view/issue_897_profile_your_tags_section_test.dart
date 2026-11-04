import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/features/capability/data/repository/capability_repository.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test(
    'PersonCapabilityCues wire maps viewerVisible for profile tags',
    () async {
      late PersonCapabilityCues cues;
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'PersonCapabilityCues': {
            '__typename': 'query_root',
            'personCapabilityCues': {
              '__typename': 'v2_v2_PersonCapabilityCuesPayload',
              'privateLabels': <String>[],
              'forwardReasonsByMe': <Object>[],
              'commitRoles': <Object>[],
              'closeAckByMe': <Object>[],
              'closeAckAboutMe': <Object>[],
              'viewerVisible': [
                {
                  '__typename': 'v2_v2_CapabilityForViewer',
                  'slug': 'transport',
                  'hasManualLabel': true,
                },
              ],
            },
          },
        },
        sent,
        (remote) async {
          cues = await CapabilityRepository(remote, _NoopRealtimeSync())
              .fetchCues(
                'U-peer00000001',
              );
        },
      );
      expect(sent.single.operationName, 'PersonCapabilityCues');
      expect(cues.viewerVisible.single.slug, 'transport');
      expect(cues.viewerVisible.single.hasManualLabel, isTrue);
    },
  );
}

final class _NoopRealtimeSync implements RealtimeSyncPort {
  @override
  Stream<RealtimeCatchUp> get catchUps => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}
}
