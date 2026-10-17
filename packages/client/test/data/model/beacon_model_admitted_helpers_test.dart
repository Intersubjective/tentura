import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/gql/_g/beacon_model.data.gql.dart';
import 'package:tentura/data/model/beacon_model.dart';

Map<String, dynamic> _json({
  required int kind,
  bool? viewerCanForward,
  int forwardPolicy = 0,
  String? lastActivityAt = '2026-02-03T04:05:06+00:00',
  String? postRootMessageId = 'M1',
  int? admittedHelpers,
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
  if (admittedHelpers != null)
    'admitted_helpers_aggregate': {
      '__typename': 'beacon_admitted_helper_aggregate',
      'aggregate': {
        '__typename': 'beacon_admitted_helper_aggregate_fields',
        'count': admittedHelpers,
      },
    },
};

/// B075 — "Coordinating" starts with the first accepted (admitted) helper, so
/// every list that renders a status from the base `BeaconModel` fragment
/// (Requests, Inbox, Activity, profile lists) needs the admitted-helper count,
/// not only the screens that fetch `BeaconModelWithAdmittedHelpers`.
void main() {
  test('base BeaconModel maps the admitted-helper count', () {
    final beacon = BeaconModel(
      GBeaconModelData.fromJson(_json(kind: 0, admittedHelpers: 2))!,
    ).toEntity();
    expect(beacon.admittedHelperCount, 2);
  });

  test('no admitted helpers maps to zero', () {
    final beacon = BeaconModel(
      GBeaconModelData.fromJson(_json(kind: 0, admittedHelpers: 0))!,
    ).toEntity();
    expect(beacon.admittedHelperCount, 0);
  });
}
