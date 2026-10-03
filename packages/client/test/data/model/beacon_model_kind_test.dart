import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/gql/_g/beacon_model.data.gql.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';

Map<String, dynamic> _json({
  required int kind,
  bool? viewerCanForward,
  int forwardPolicy = 0,
  String? lastActivityAt = '2026-02-03T04:05:06+00:00',
  String? postRootMessageId = 'M1',
}) => {
  '__typename': 'beacon',
  'id': 'B1',
  'cover_source': 0,
  'title': 't',
  'description': 'd',
  'needs': '',
  'created_at': '2026-01-01T00:00:00+00:00',
  'updated_at': '2026-01-01T00:00:00+00:00',
  'status': 0,
  'tags': '',
  'beacon_images': <dynamic>[],
  'author': {
    '__typename': 'user',
    'id': 'U1',
    'display_name': 'A',
    'description': '',
  },
  'help_offers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'unanswered_help_offers': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'is_discoverable': true,
  'kind': kind,
  'forward_policy': forwardPolicy,
  'last_activity_at': lastActivityAt,
  'post_root_message_id': postRootMessageId,
  'viewer_can_forward': viewerCanForward,
};

void main() {
  group('BeaconModel mapper kind fields', () {
    test('kind 1 maps to a Post with its Post-only fields', () {
      final beacon = BeaconModel(
        GBeaconModelData.fromJson(_json(kind: 1, viewerCanForward: true))!,
      ).toEntity();
      expect(beacon.kind, BeaconKind.post);
      expect(beacon.isRequest, isFalse);
      expect(beacon.postRootMessageId, 'M1');
      expect(beacon.viewerCanForward, isTrue);
      expect(beacon.lastActivityAt, DateTime.utc(2026, 2, 3, 4, 5, 6));
    });

    test('forward policy wire values map to the policy enum', () {
      BeaconModel model(int policy) => BeaconModel(
        GBeaconModelData.fromJson(_json(kind: 0, forwardPolicy: policy))!,
      );
      expect(model(0).toEntity().forwardPolicy, BeaconForwardPolicyValue.closed);
      expect(model(1).toEntity().forwardPolicy, BeaconForwardPolicyValue.open);
    });

    test('absent Post-only fields map to null', () {
      final beacon = BeaconModel(
        GBeaconModelData.fromJson(
          _json(kind: 0, lastActivityAt: null, postRootMessageId: null),
        )!,
      ).toEntity();
      expect(beacon.lastActivityAt, isNull);
      expect(beacon.postRootMessageId, isNull);
    });

    test('kind 0 maps to a Request', () {
      final beacon = BeaconModel(
        GBeaconModelData.fromJson(_json(kind: 0))!,
      ).toEntity();
      expect(beacon.kind, BeaconKind.request);
      expect(beacon.isRequest, isTrue);
    });
  });
}
