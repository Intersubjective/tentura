import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';

TagBeaconRef _ref(String slug, {String beaconId = 'B1'}) => TagBeaconRef(
  slug: slug,
  beaconId: beaconId,
  beaconTitle: 'Beacon',
  createdAt: '2026-01-01T00:00:00Z',
);

PersonCapabilityCues _cues({
  List<String> privateLabels = const [],
  List<TagCount> forwardReasonsByMe = const [],
  List<TagBeaconRef> commitRoles = const [],
  List<TagBeaconRef> closeAckByMe = const [],
  List<TagBeaconRef> closeAckAboutMe = const [],
  List<CapabilityWithSource> viewerVisible = const [],
}) =>
    PersonCapabilityCues(
      privateLabels: privateLabels,
      forwardReasonsByMe: forwardReasonsByMe,
      commitRoles: commitRoles,
      closeAckByMe: closeAckByMe,
      closeAckAboutMe: closeAckAboutMe,
      viewerVisible: viewerVisible,
    );

void main() {
  group('slugsFromBeaconRefs', () {
    test('dedupes slugs and preserves first-seen order', () {
      expect(
        PersonCapabilityCues.slugsFromBeaconRefs([
          _ref('transport'),
          _ref('money', beaconId: 'B2'),
          _ref('transport', beaconId: 'B3'),
        ]),
        ['transport', 'money'],
      );
    });

    test('returns empty for empty input', () {
      expect(PersonCapabilityCues.slugsFromBeaconRefs([]), isEmpty);
    });
  });

  group('forwardedForSlugs', () {
    test('maps slugs from tag counts in server order', () {
      final cues = _cues(
        forwardReasonsByMe: const [
          TagCount(slug: 'money', count: 3, lastSeenAt: '2026-01-03'),
          TagCount(slug: 'transport', count: 1, lastSeenAt: '2026-01-01'),
        ],
      );
      expect(cues.forwardedForSlugs, ['money', 'transport']);
    });
  });

  group('strongestNetworkCueSlugs', () {
    test('prefers closeAck over commit, forward, and private labels', () {
      final cues = _cues(
        privateLabels: ['pets'],
        forwardReasonsByMe: const [
          TagCount(slug: 'money', count: 2, lastSeenAt: '2026-01-01'),
        ],
        commitRoles: [_ref('transport')],
        closeAckByMe: [_ref('food')],
      );
      expect(cues.strongestNetworkCueSlugs, ['food']);
    });

    test('prefers commitRole over forward and private labels', () {
      final cues = _cues(
        privateLabels: ['pets'],
        forwardReasonsByMe: const [
          TagCount(slug: 'money', count: 2, lastSeenAt: '2026-01-01'),
        ],
        commitRoles: [_ref('transport')],
      );
      expect(cues.strongestNetworkCueSlugs, ['transport']);
    });

    test('prefers forwardReason over private labels', () {
      final cues = _cues(
        privateLabels: ['pets'],
        forwardReasonsByMe: const [
          TagCount(slug: 'money', count: 2, lastSeenAt: '2026-01-01'),
        ],
      );
      expect(cues.strongestNetworkCueSlugs, ['money']);
    });

    test('falls back to private labels', () {
      final cues = _cues(privateLabels: ['pets', 'food']);
      expect(cues.strongestNetworkCueSlugs, ['pets', 'food']);
    });

    test('returns empty when all cue tiers are empty', () {
      expect(_cues().strongestNetworkCueSlugs, isEmpty);
    });
  });

  group('profileBeaconCueSlugs', () {
    test('prefers closeAckAboutMe over commitRoles', () {
      final cues = _cues(
        closeAckAboutMe: [_ref('food')],
        commitRoles: [_ref('transport')],
      );
      expect(cues.profileBeaconCueSlugs, ['food']);
    });

    test('falls back to commitRoles when closeAckAboutMe is empty', () {
      final cues = _cues(
        commitRoles: [_ref('transport'), _ref('transport', beaconId: 'B2')],
      );
      expect(cues.profileBeaconCueSlugs, ['transport']);
    });
  });

  group('automaticViewerVisibleSlugs', () {
    test('includes only non-manual viewer-visible slugs', () {
      final cues = _cues(
        viewerVisible: const [
          CapabilityWithSource(slug: 'transport', hasManualLabel: false),
          CapabilityWithSource(slug: 'money', hasManualLabel: true),
          CapabilityWithSource(slug: 'food', hasManualLabel: false),
        ],
      );
      expect(cues.automaticViewerVisibleSlugs, {'transport', 'food'});
    });
  });

  group('groupSlugsByCapabilityGroup', () {
    test('groups known slugs by capability group in enum tag order', () {
      final grouped = PersonCapabilityCues.groupSlugsByCapabilityGroup([
        'money',
        'transport',
        'calls',
        'unknown_slug',
      ]);

      expect(grouped.keys, [
        CapabilityGroup.logistics,
        CapabilityGroup.communication,
        CapabilityGroup.resources,
      ]);
      expect(grouped[CapabilityGroup.logistics], ['transport']);
      expect(grouped[CapabilityGroup.communication], ['calls']);
      expect(grouped[CapabilityGroup.resources], ['money']);
    });

    test('omits groups with no matching slugs', () {
      final grouped = PersonCapabilityCues.groupSlugsByCapabilityGroup(['pets']);
      expect(grouped.keys, [CapabilityGroup.care]);
      expect(grouped[CapabilityGroup.care], ['pets']);
    });

    test('returns empty map for only unknown slugs', () {
      expect(
        PersonCapabilityCues.groupSlugsByCapabilityGroup(['not_a_tag']),
        isEmpty,
      );
    });
  });

  group('isEmpty', () {
    test('is true when legacy cue fields are all empty', () {
      expect(
        _cues(
          viewerVisible: const [
            CapabilityWithSource(slug: 'transport', hasManualLabel: true),
          ],
        ).isEmpty,
        isTrue,
      );
    });

    test('is false when any legacy cue field is populated', () {
      expect(
        _cues(
          forwardReasonsByMe: const [
            TagCount(slug: 'money', count: 1, lastSeenAt: '2026-01-01'),
          ],
        ).isEmpty,
        isFalse,
      );
    });
  });
}
