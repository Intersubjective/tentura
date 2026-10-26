import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/gql/_g/beacon_model.data.gql.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';

final _now = DateTime.utc(2026, 10, 26, 12);

Map<String, dynamic> _row(String? expiresAt) => {
  '__typename': 'beacon',
  'id': 'Bpost00000001',
  'cover_source': 0,
  'title': '',
  'description': '',
  'needs': '',
  'created_at': '2026-10-25T12:00:00+00:00',
  'updated_at': '2026-10-26T12:00:00+00:00',
  'status': 0,
  'tags': '',
  'beacon_images': <dynamic>[],
  'active_help_offers': <dynamic>[],
  'participant_help_offers': <dynamic>[],
  'author': {
    '__typename': 'user',
    'id': 'Uauthor000001',
    'display_name': 'Author',
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
  'admitted_helpers_aggregate': {
    '__typename': 'beacon_admitted_helper_aggregate',
    'aggregate': null,
  },
  'is_discoverable': false,
  'kind': 1,
  'forward_policy': 1,
  'expires_at': expiresAt,
};

void main() {
  group('Beacon expiry mapping', () {
    for (final expiresAt in ['2026-10-26T16:00:00+02:00', null]) {
      test('preserves Hasura expires_at $expiresAt', () {
        final beacon = BeaconModel(
          GBeaconModelData.fromJson(_row(expiresAt))!,
        ).toEntity();
        expect(
          beacon.expiresAt,
          expiresAt == null ? null : DateTime.utc(2026, 10, 26, 14),
        );
      });
    }
  });

  group('Beacon Post archive policy', () {
    for (final kind in BeaconKind.values) {
      for (final status in BeaconStatus.values) {
        for (final entry in <String, DateTime?>{
          'missing': null,
          'future': _now.add(const Duration(microseconds: 1)),
          'equal': _now,
          'past': _now.subtract(const Duration(microseconds: 1)),
        }.entries) {
          test('${kind.name} ${status.name} with ${entry.key} expiry', () {
            final beacon = Beacon(
              createdAt: _now.subtract(const Duration(days: 3)),
              updatedAt: _now,
              lastActivityAt: _now,
              kind: kind,
              status: status,
              expiresAt: entry.value,
            );
            final expected =
                kind == BeaconKind.post &&
                (status == BeaconStatus.closed ||
                    (status == BeaconStatus.open &&
                        (entry.key == 'equal' || entry.key == 'past')));
            expect(beacon.isPostArchivedAt(_now), expected);
          });
        }
      }
    }
  });
}
