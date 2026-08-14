import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/domain/forward_draft_policy.dart';

void main() {
  group('uncoveredRecipientIds', () {
    final cases = <({
      String name,
      Set<String> selectedIds,
      Map<String, String> perRecipientNotes,
      Set<String> skippedPersonalNoteIds,
      Set<String> expected,
    })>[
      (
        name: 'selected with partial notes',
        selectedIds: {'a', 'b'},
        perRecipientNotes: {'a': 'hi'},
        skippedPersonalNoteIds: {},
        expected: {'b'},
      ),
      (
        name: 'skip removes whitespace-only note from uncovered',
        selectedIds: {'a'},
        perRecipientNotes: {'a': '  '},
        skippedPersonalNoteIds: {'a'},
        expected: {},
      ),
      (
        name: 'skip removes typed note from uncovered',
        selectedIds: {'a'},
        perRecipientNotes: {'a': 'typed'},
        skippedPersonalNoteIds: {'a'},
        expected: {},
      ),
      (
        name: 'empty personal note is uncovered',
        selectedIds: {'a'},
        perRecipientNotes: {'a': ''},
        skippedPersonalNoteIds: {},
        expected: {'a'},
      ),
      (
        name: 'whitespace personal note is uncovered',
        selectedIds: {'a'},
        perRecipientNotes: {'a': '   '},
        skippedPersonalNoteIds: {},
        expected: {'a'},
      ),
      (
        name: 'missing personal note is uncovered',
        selectedIds: {'a'},
        perRecipientNotes: {},
        skippedPersonalNoteIds: {},
        expected: {'a'},
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        expect(
          uncoveredRecipientIds(
            selectedIds: c.selectedIds,
            perRecipientNotes: c.perRecipientNotes,
            skippedPersonalNoteIds: c.skippedPersonalNoteIds,
          ),
          c.expected,
        );
      });
    }
  });

  group('effectiveForwardNote', () {
    final cases = <({
      String name,
      String? personal,
      String? shared,
      String? expected,
    })>[
      (
        name: 'personal trims and wins over shared',
        personal: ' p ',
        shared: 's',
        expected: 'p',
      ),
      (
        name: 'whitespace personal falls back to shared',
        personal: '  ',
        shared: 's',
        expected: 's',
      ),
      (
        name: 'both null returns null',
        personal: null,
        shared: null,
        expected: null,
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        expect(
          effectiveForwardNote(personal: c.personal, shared: c.shared),
          c.expected,
        );
      });
    }
  });

  group('forwardEdgeIsCancellable', () {
    final readAt = DateTime.utc(2026, 8, 14);

    test('all blockers false and readAt null returns true', () {
      expect(
        forwardEdgeIsCancellable(
          recipientReadAt: null,
          hasOnwardChild: false,
          recipientHasActiveHelpOffer: false,
          recipientDeclined: false,
        ),
        isTrue,
      );
    });

    final blockerCases = <({
      String name,
      DateTime? recipientReadAt,
      bool hasOnwardChild,
      bool recipientHasActiveHelpOffer,
      bool recipientDeclined,
    })>[
      (
        name: 'recipientReadAt non-null',
        recipientReadAt: readAt,
        hasOnwardChild: false,
        recipientHasActiveHelpOffer: false,
        recipientDeclined: false,
      ),
      (
        name: 'hasOnwardChild',
        recipientReadAt: null,
        hasOnwardChild: true,
        recipientHasActiveHelpOffer: false,
        recipientDeclined: false,
      ),
      (
        name: 'recipientHasActiveHelpOffer',
        recipientReadAt: null,
        hasOnwardChild: false,
        recipientHasActiveHelpOffer: true,
        recipientDeclined: false,
      ),
      (
        name: 'recipientDeclined',
        recipientReadAt: null,
        hasOnwardChild: false,
        recipientHasActiveHelpOffer: false,
        recipientDeclined: true,
      ),
    ];

    for (final c in blockerCases) {
      test('${c.name} alone returns false', () {
        expect(
          forwardEdgeIsCancellable(
            recipientReadAt: c.recipientReadAt,
            hasOnwardChild: c.hasOnwardChild,
            recipientHasActiveHelpOffer: c.recipientHasActiveHelpOffer,
            recipientDeclined: c.recipientDeclined,
          ),
          isFalse,
        );
      });
    }
  });

  group('shouldNudgeOfferHelpAfterForwardVisit', () {
    test('no new edge after visit does not nudge', () {
      expect(
        shouldNudgeOfferHelpAfterForwardVisit(
          hadOutgoingEdgeBefore: false,
          hasOutgoingEdgeAfter: false,
          offerHelpAllowed: true,
        ),
        isFalse,
      );
    });

    test('already had edge before visit does not nudge', () {
      expect(
        shouldNudgeOfferHelpAfterForwardVisit(
          hadOutgoingEdgeBefore: true,
          hasOutgoingEdgeAfter: true,
          offerHelpAllowed: true,
        ),
        isFalse,
      );
    });

    test('false to true edge transition nudges when offer help allowed', () {
      expect(
        shouldNudgeOfferHelpAfterForwardVisit(
          hadOutgoingEdgeBefore: false,
          hasOutgoingEdgeAfter: true,
          offerHelpAllowed: true,
        ),
        isTrue,
      );
    });

    test('false to true edge does not nudge when offer help not allowed', () {
      expect(
        shouldNudgeOfferHelpAfterForwardVisit(
          hadOutgoingEdgeBefore: false,
          hasOutgoingEdgeAfter: true,
          offerHelpAllowed: false,
        ),
        isFalse,
      );
    });
  });
}
