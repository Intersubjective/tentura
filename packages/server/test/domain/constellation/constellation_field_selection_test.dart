import 'package:test/test.dart';

import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';

void main() {
  group('classifyAuthorizedPinnedBeacon lifecycle', () {
    const showClosed = false;
    const participatedOnly = false;

    test('statuses 0, 7, 8 are visible with default filters', () {
      for (final status in [0, 7, 8]) {
        expect(
          classifyAuthorizedPinnedBeacon(
            status: status,
            showClosed: showClosed,
            participatedOnly: participatedOnly,
            viewerParticipates: false,
          ),
          ConstellationPinnedBeaconLayer.visiblePinned,
          reason: 'status $status',
        );
      }
    });

    test('statuses 5, 4, 6 are filter-hidden when showClosed is false', () {
      for (final status in [5, 4, 6]) {
        expect(
          classifyAuthorizedPinnedBeacon(
            status: status,
            showClosed: showClosed,
            participatedOnly: participatedOnly,
            viewerParticipates: true,
          ),
          ConstellationPinnedBeaconLayer.filterHidden,
          reason: 'status $status',
        );
      }
    });

    test('statuses 5, 4, 6 are visible when showClosed is true', () {
      for (final status in [5, 4, 6]) {
        expect(
          classifyAuthorizedPinnedBeacon(
            status: status,
            showClosed: true,
            participatedOnly: participatedOnly,
            viewerParticipates: true,
          ),
          ConstellationPinnedBeaconLayer.visiblePinned,
          reason: 'status $status',
        );
      }
    });

    test('cancelled and unknown statuses stay dormant', () {
      for (final status in [1, 3, 99]) {
        expect(
          classifyAuthorizedPinnedBeacon(
            status: status,
            showClosed: true,
            participatedOnly: false,
            viewerParticipates: true,
          ),
          ConstellationPinnedBeaconLayer.dormantAnchor,
          reason: 'status $status',
        );
      }
    });
  });

  group('classifyAuthorizedPinnedBeacon participatedOnly', () {
    test('excludes non-participants when lifecycle permits', () {
      expect(
        classifyAuthorizedPinnedBeacon(
          status: 0,
          showClosed: false,
          participatedOnly: true,
          viewerParticipates: false,
        ),
        ConstellationPinnedBeaconLayer.filterHidden,
      );
    });

    test('includes participants when lifecycle permits', () {
      expect(
        classifyAuthorizedPinnedBeacon(
          status: 0,
          showClosed: false,
          participatedOnly: true,
          viewerParticipates: true,
        ),
        ConstellationPinnedBeaconLayer.visiblePinned,
      );
    });
  });
}
