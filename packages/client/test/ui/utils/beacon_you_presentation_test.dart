import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_you_presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('buildBeaconYouPresentation', () {
    test('returns ordered segments with labels when not collapsed', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 2,
        promiseOpen: 1,
      );
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.noOpenItems,
        showNewBadges: true,
      );
      expect(p.fallbackText, isNull);
      expect(p.segments, hasLength(2));
      expect(p.segments.first.icon, isNotNull);
      expect(p.segments.first.label, isNotNull);
      expect(p.segments.first.count, 2);
    });

    test('orders ask → promise → blocker → review segments', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        reviewOpen: 1,
        blockerOpen: 1,
        promiseOpen: 1,
        askOpen: 1,
      );
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: false,
      );
      expect(
        p.segments.map((s) => s.count).toList(),
        [1, 1, 1, 1],
      );
      expect(p.segments[0].label, l10n.beaconYouAskCount(1));
      expect(p.segments[1].label, l10n.beaconYouPromiseCount(1));
      expect(p.segments[2].label, l10n.beaconYouBlockerCount(1));
      expect(p.segments[3].label, l10n.beaconYouReviewCount(1));
    });

    test('uses singular and plural ICU labels', () {
      const single = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 1,
      );
      const plural = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 3,
      );
      final pSingle = buildBeaconYouPresentation(
        l10n,
        single,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: false,
      );
      final pPlural = buildBeaconYouPresentation(
        l10n,
        plural,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: false,
      );
      expect(pSingle.segments.single.label, l10n.beaconYouAskCount(1));
      expect(pPlural.segments.single.label, l10n.beaconYouAskCount(3));
      expect(pSingle.segments.single.label, isNot(pPlural.segments.single.label));
    });

    test('collapse hides labels but keeps counts and new badges', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        blockerOpen: 1,
        blockerNew: 2,
      );
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: true,
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: true,
      );
      expect(p.segments.single.label, isNull);
      expect(p.segments.single.count, 1);
      expect(p.segments.single.newCount, 2);
    });

    test('showNewBadges false clears segment new counts', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 1,
        askNew: 4,
      );
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: false,
      );
      expect(p.segments.single.newCount, 0);
    });

    test('empty responsibility uses waitingOnOthers fallback', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        othersOpenCount: 3,
      );
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.waitingOnOthers,
        showNewBadges: false,
      );
      expect(p.fallbackText, l10n.beaconYouWaitingOnOthers);
      expect(p.segments, isEmpty);
    });

    test('empty responsibility uses noOpenItems fallback', () {
      const r = CoordinationResponsibility(beaconId: 'b1');
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.noOpenItems,
        showNewBadges: false,
      );
      expect(p.fallbackText, l10n.beaconYouNoOpenItems);
    });

    test('empty responsibility uses enoughHelp fallback', () {
      const r = CoordinationResponsibility(beaconId: 'b1');
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.enoughHelp,
        showNewBadges: false,
      );
      expect(p.fallbackText, l10n.beaconYouEnoughHelp);
    });

    test('empty responsibility uses closed fallback', () {
      const r = CoordinationResponsibility(beaconId: 'b1');
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.closed,
        showNewBadges: false,
      );
      expect(p.fallbackText, l10n.beaconYouClosed);
    });

    test('empty responsibility hidden produces isHidden presentation', () {
      const r = CoordinationResponsibility(beaconId: 'b1');
      final p = buildBeaconYouPresentation(
        l10n,
        r,
        collapse: false,
        emptyFallback: BeaconYouEmptyFallback.hidden,
        showNewBadges: false,
      );
      expect(p.isHidden, isTrue);
      expect(p.fallbackText, isNull);
      expect(p.segments, isEmpty);
    });
  });

  group('deriveBeaconYouEmptyFallback', () {
    test('closed lifecycle returns closed', () {
      expect(
        deriveBeaconYouEmptyFallback(
          lifecycle: BeaconLifecycle.closed,
          isAuthorOrSteward: false,
          othersOpenCount: 0,
          compactSurface: false,
        ),
        BeaconYouEmptyFallback.closed,
      );
    });

    test('othersOpenCount returns waitingOnOthers', () {
      expect(
        deriveBeaconYouEmptyFallback(
          lifecycle: BeaconLifecycle.open,
          isAuthorOrSteward: false,
          othersOpenCount: 2,
          compactSurface: false,
        ),
        BeaconYouEmptyFallback.waitingOnOthers,
      );
    });

    test('non-author on open beacon returns enoughHelp', () {
      expect(
        deriveBeaconYouEmptyFallback(
          lifecycle: BeaconLifecycle.open,
          isAuthorOrSteward: false,
          othersOpenCount: 0,
          compactSurface: false,
        ),
        BeaconYouEmptyFallback.enoughHelp,
      );
    });

    test('compact surface returns hidden', () {
      expect(
        deriveBeaconYouEmptyFallback(
          lifecycle: BeaconLifecycle.open,
          isAuthorOrSteward: false,
          othersOpenCount: 0,
          compactSurface: true,
        ),
        BeaconYouEmptyFallback.hidden,
      );
    });

    test('author with no items returns noOpenItems', () {
      expect(
        deriveBeaconYouEmptyFallback(
          lifecycle: BeaconLifecycle.open,
          isAuthorOrSteward: true,
          othersOpenCount: 0,
          compactSurface: false,
        ),
        BeaconYouEmptyFallback.noOpenItems,
      );
    });
  });
}
