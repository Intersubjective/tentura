import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon/data/repository/post_publish_repository.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  group('Post publication lifetime transport', () {
    for (final hours in [1, 3, 6, 72]) {
      test(
        'publishing with a $hours hour lifetime sends lifetimeHours',
        () async {
          final sent = <WireSent>[];
          await withRemoteWire(
            {
              'PostPublish': {
                '__typename': 'mutation_root',
                'postPublish': {
                  '__typename': 'v2_PostPublishResult',
                  'beaconId': 'Bpost00000001',
                  'rootMessageId': 'Mroot00000001',
                },
              },
            },
            sent,
            (remote) async {
              // Exercise the use case, port, repository and Ferry serialization.
              final result =
                  await PostPublishCase(
                    PostPublishRepository(remote),
                  ).publish(
                    beaconId: 'Bpost00000001',
                    body: 'Who has a ladder?',
                    mentions: const [],
                    recipientIds: const {'Urecipient001'},
                    notes: const {},
                    forwardPolicy: BeaconForwardPolicyValue.open,
                    lifetime: Duration(hours: hours),
                  );
              expect(result.beaconId, 'Bpost00000001');
              expect(result.rootMessageId, 'Mroot00000001');
            },
          );

          expect(sent, hasLength(1));
          expect(sent.single.operationName, 'PostPublish');
          expect(sent.single.variables['lifetimeHours'], hours);
        },
      );
    }
  });
}
