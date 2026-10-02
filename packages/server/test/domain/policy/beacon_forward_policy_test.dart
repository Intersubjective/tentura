import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/policy/beacon_forward_policy.dart';

const _authorId = 'Uauthor';
const _otherId = 'Uother';

BeaconEntity _beacon({
  required BeaconKind kind,
  required BeaconForwardPolicyValue policy,
  BeaconStatus status = BeaconStatus.open,
}) => BeaconEntity(
  id: 'B1',
  title: kind == BeaconKind.post ? '' : 'Title',
  author: const UserEntity(id: _authorId),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  status: status,
  kind: kind,
  forwardPolicy: policy,
);

void main() {
  group('BeaconForwardPolicy.canForward', () {
    group('Request', () {
      final request = _beacon(
        kind: BeaconKind.request,
        policy: BeaconForwardPolicyValue.open,
      );

      test('lets any sender forward an open Request', () {
        expect(
          BeaconForwardPolicy.canForward(beacon: request, senderId: _otherId),
          isTrue,
        );
        expect(
          BeaconForwardPolicy.canForward(beacon: request, senderId: _authorId),
          isTrue,
        );
      });
    });

    group('Post with open forwarding', () {
      final post = _beacon(
        kind: BeaconKind.post,
        policy: BeaconForwardPolicyValue.open,
      );

      test('lets a non-author forward', () {
        expect(
          BeaconForwardPolicy.canForward(beacon: post, senderId: _otherId),
          isTrue,
        );
      });

      test('lets the author forward', () {
        expect(
          BeaconForwardPolicy.canForward(beacon: post, senderId: _authorId),
          isTrue,
        );
      });
    });

    group('Post with closed forwarding', () {
      final post = _beacon(
        kind: BeaconKind.post,
        policy: BeaconForwardPolicyValue.closed,
      );

      test('refuses a non-author', () {
        expect(
          BeaconForwardPolicy.canForward(beacon: post, senderId: _otherId),
          isFalse,
        );
      });

      test('lets only the author forward', () {
        expect(
          BeaconForwardPolicy.canForward(beacon: post, senderId: _authorId),
          isTrue,
        );
      });
    });

    group('outside the open family', () {
      const closedFamily = [
        BeaconStatus.cancelled,
        BeaconStatus.deleted,
        BeaconStatus.draft,
        BeaconStatus.reviewOpen,
        BeaconStatus.closed,
      ];

      for (final status in closedFamily) {
        test('refuses everyone on an open-policy Post that is $status', () {
          final post = _beacon(
            kind: BeaconKind.post,
            policy: BeaconForwardPolicyValue.open,
            status: status,
          );
          expect(
            BeaconForwardPolicy.canForward(beacon: post, senderId: _otherId),
            isFalse,
          );
          expect(
            BeaconForwardPolicy.canForward(beacon: post, senderId: _authorId),
            isFalse,
          );
        });

        test('refuses everyone on a Request that is $status', () {
          final request = _beacon(
            kind: BeaconKind.request,
            policy: BeaconForwardPolicyValue.open,
            status: status,
          );
          expect(
            BeaconForwardPolicy.canForward(
              beacon: request,
              senderId: _otherId,
            ),
            isFalse,
          );
          expect(
            BeaconForwardPolicy.canForward(
              beacon: request,
              senderId: _authorId,
            ),
            isFalse,
          );
        });
      }

      test('refuses the author of a closed-policy Post that is cancelled', () {
        final post = _beacon(
          kind: BeaconKind.post,
          policy: BeaconForwardPolicyValue.closed,
          status: BeaconStatus.cancelled,
        );
        expect(
          BeaconForwardPolicy.canForward(beacon: post, senderId: _authorId),
          isFalse,
        );
      });
    });

    group('open-family statuses', () {
      for (final status in [
        BeaconStatus.open,
        BeaconStatus.needsMoreHelp,
        BeaconStatus.enoughHelp,
      ]) {
        test('lets anyone forward an open-policy Post that is $status', () {
          final post = _beacon(
            kind: BeaconKind.post,
            policy: BeaconForwardPolicyValue.open,
            status: status,
          );
          expect(
            BeaconForwardPolicy.canForward(beacon: post, senderId: _otherId),
            isTrue,
          );
        });
      }
    });
  });
}
