import 'package:test/test.dart';
import 'package:tentura_root/domain/capability/capability_slugs.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';

void main() {
  group('shared capability slug order', () {
    test('has exactly 37 slugs', () {
      expect(kCapabilitySlugOrder, hasLength(37));
      expect(kCapabilitySlugOrder.toSet(), hasLength(37));
    });

    test('server allowed set equals ordered list', () {
      expect(kAllowedCapabilitySlugs, equals(kCapabilitySlugOrder.toSet()));
      expect(kAllowedCapabilitySlugs, isNot(same(kCapabilitySlugOrder)));
    });

    test('canonicalFirstCapabilitySlug picks lowest rank', () {
      expect(
        canonicalFirstCapabilitySlug(['other', 'transport', 'food']),
        'transport',
      );
      expect(
        canonicalFirstCapabilitySlug(['job', 'gig', 'orders']),
        'orders',
      );
      expect(canonicalFirstCapabilitySlug(['unknown']), isNull);
      expect(canonicalFirstCapabilitySlug(const <String>[]), isNull);
    });

    test('rank map matches order indices', () {
      for (var i = 0; i < kCapabilitySlugOrder.length; i++) {
        expect(kCapabilitySlugRank[kCapabilitySlugOrder[i]], i);
      }
    });
  });

  group('BeaconCoverSource wire contract', () {
    test('parse accepts explicit wire values', () {
      expect(BeaconCoverSource.parse(0), BeaconCoverSource.photo);
      expect(BeaconCoverSource.parse(1), BeaconCoverSource.symbol);
      expect(BeaconCoverSource.photo.wireValue, 0);
      expect(BeaconCoverSource.symbol.wireValue, 1);
    });

    test('parse rejects unknown values', () {
      expect(() => BeaconCoverSource.parse(2), throwsArgumentError);
      expect(() => BeaconCoverSource.parse(-1), throwsArgumentError);
    });

    test('fromWireOrPhoto tolerates null and unknown', () {
      expect(BeaconCoverSource.fromWireOrPhoto(null), BeaconCoverSource.photo);
      expect(BeaconCoverSource.fromWireOrPhoto(0), BeaconCoverSource.photo);
      expect(BeaconCoverSource.fromWireOrPhoto(1), BeaconCoverSource.symbol);
      expect(BeaconCoverSource.fromWireOrPhoto(99), BeaconCoverSource.photo);
    });
  });
}
