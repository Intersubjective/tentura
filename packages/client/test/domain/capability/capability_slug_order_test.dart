import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura_root/domain/capability/capability_slugs.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

void main() {
  group('shared capability slug order', () {
    test('has exactly 37 slugs matching CapabilityTag enum order', () {
      expect(kCapabilitySlugOrder, hasLength(37));
      expect(
        kCapabilitySlugOrder,
        equals([for (final tag in CapabilityTag.values) tag.slug]),
      );
    });

    test('client enum covers seven groups', () {
      expect(CapabilityGroup.values, hasLength(7));
      final groups = {for (final tag in CapabilityTag.values) tag.group};
      expect(groups, unorderedEquals(CapabilityGroup.values));
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
      expect(canonicalFirstCapabilitySlug(['unknown', 'also_bad']), isNull);
      expect(canonicalFirstCapabilitySlug(const <String>[]), isNull);
    });

    test('fromSlug still resolves every ordered slug', () {
      for (final slug in kCapabilitySlugOrder) {
        final tag = CapabilityTag.fromSlug(slug);
        expect(tag, isNotNull, reason: slug);
        expect(tag!.slug, slug);
        expect(tag.icon, isNotNull);
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
