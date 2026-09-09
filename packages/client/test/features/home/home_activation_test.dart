import 'package:test/test.dart';

import 'package:tentura/features/home/domain/entity/home_activation.dart';

void main() {
  group('HomeActivationSignals.isSettled', () {
    test('is false until My Work is loaded', () {
      const signals = HomeActivationSignals(
        myWorkLoaded: false,
        inboxLoaded: true,
      );
      expect(signals.isSettled, isFalse);
    });

    test('is false until Inbox is loaded or failed', () {
      const signals = HomeActivationSignals(
        myWorkLoaded: true,
        inboxLoaded: false,
        inboxFailed: false,
      );
      expect(signals.isSettled, isFalse);
    });

    test('is true when My Work is loaded and Inbox is loaded', () {
      const signals = HomeActivationSignals(
        myWorkLoaded: true,
        inboxLoaded: true,
      );
      expect(signals.isSettled, isTrue);
    });

    test('is true when My Work is loaded and Inbox failed', () {
      const signals = HomeActivationSignals(
        myWorkLoaded: true,
        inboxFailed: true,
      );
      expect(signals.isSettled, isTrue);
    });
  });

  group('HomeActivationSignals.activityCount', () {
    test('excludes draftCount when not reflected in myWorkCardCount', () {
      const signals = HomeActivationSignals(
        myWorkCardCount: 0,
        draftCount: 3,
        archivedCountHint: 0,
        inboxItemCount: 0,
      );

      expect(signals.activityCount, 0);
      expect(signals.hasActivity, isFalse);
    });

    test('sums myWorkCardCount, archivedCountHint, and inboxItemCount', () {
      const signals = HomeActivationSignals(
        myWorkCardCount: 2,
        draftCount: 1,
        archivedCountHint: 1,
        inboxItemCount: 3,
      );

      expect(signals.myWorkActivityCount, 3);
      expect(signals.activityCount, 6);
    });
  });

  group('HomeActivationSignals.hasActivity', () {
    test('is false on an all-zero settled snapshot', () {
      const signals = HomeActivationSignals(
        myWorkLoaded: true,
        inboxLoaded: true,
      );

      expect(signals.isSettled, isTrue);
      expect(signals.hasActivity, isFalse);
    });
  });

  group('HomeActivationSignals.hasProvenActivity', () {
    test('is true for loaded My Work with cards while Inbox is still unloaded',
        () {
      const signals = HomeActivationSignals(
        myWorkCardCount: 1,
        myWorkLoaded: true,
        inboxLoaded: false,
      );

      expect(signals.hasProvenActivity, isTrue);
    });

    test('is true for loaded Inbox with items while My Work is unloaded', () {
      const signals = HomeActivationSignals(
        inboxItemCount: 2,
        myWorkLoaded: false,
        inboxLoaded: true,
      );

      expect(signals.hasProvenActivity, isTrue);
    });

    test('is false when both projections are loaded with zero activity', () {
      const signals = HomeActivationSignals(
        myWorkLoaded: true,
        inboxLoaded: true,
      );

      expect(signals.hasProvenActivity, isFalse);
    });
  });
}
