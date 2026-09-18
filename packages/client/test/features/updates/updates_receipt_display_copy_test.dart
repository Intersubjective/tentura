import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

void main() {
  final l10n = L10nEn();

  test('blank title uses presentation-key fallback', () {
    final copy = resolveUpdatesReceiptDisplayCopy(
      title: '',
      body: 'Body line',
      presentationKey: 'needs_me',
      l10n: l10n,
    );

    expect(copy.title, l10n.updatesFallbackTitleNeedsMe);
    expect(copy.body, 'Body line');
  });

  test('blank body uses presentation-key fallback', () {
    final copy = resolveUpdatesReceiptDisplayCopy(
      title: 'Title line',
      body: '   ',
      presentationKey: 'commitment_accepted',
      l10n: l10n,
    );

    expect(copy.title, 'Title line');
    expect(copy.body, l10n.updatesFallbackBodyCommitmentAccepted);
  });

  test('both blank use keyed fallbacks', () {
    final copy = resolveUpdatesReceiptDisplayCopy(
      title: '',
      body: '',
      presentationKey: 'relay_received',
      l10n: l10n,
    );

    expect(copy.title, l10n.updatesFallbackTitleRelayReceived);
    expect(copy.body, l10n.updatesFallbackBodyRelayReceived);
  });

  test('unknown presentation key uses generic fallbacks', () {
    final copy = resolveUpdatesReceiptDisplayCopy(
      title: '',
      body: '',
      presentationKey: 'future_server_key',
      l10n: l10n,
    );

    expect(copy.title, l10n.updatesFallbackTitleGeneric);
    expect(copy.body, l10n.updatesFallbackBodyGeneric);
  });

  test('trust change presentation keys use grouped fallbacks', () {
    final given = resolveUpdatesReceiptDisplayCopy(
      title: '',
      body: '',
      presentationKey: 'trust_given_changed_down',
      l10n: l10n,
    );
    final received = resolveUpdatesReceiptDisplayCopy(
      title: '',
      body: '',
      presentationKey: 'trust_received_changed_neutral',
      l10n: l10n,
    );

    expect(given.title, l10n.updatesFallbackTitleTrustGivenChanged);
    expect(given.body, l10n.updatesFallbackBodyTrustGivenChanged);
    expect(received.title, l10n.updatesFallbackTitleTrustReceivedChanged);
    expect(received.body, l10n.updatesFallbackBodyTrustReceivedChanged);
  });

  test('beaconTitleFromPresentationPayload reads beacon title', () {
    expect(
      beaconTitleFromPresentationPayload(
        '{"beaconTitle":"Garden cleanup","eventType":"needsMe"}',
      ),
      'Garden cleanup',
    );
    expect(beaconTitleFromPresentationPayload('{}'), isNull);
    expect(beaconTitleFromPresentationPayload('not-json'), isNull);
  });

  test('feed row copy uses beacon title as headline and keeps excerpt', () {
    final copy = resolveUpdatesFeedRowCopy(
      title: 'Alex accepted your ask',
      body: 'Garden cleanup — Bring tools',
      presentationKey: 'commitment_accepted',
      presentationPayloadJson:
          '{"beaconTitle":"Garden cleanup","eventType":"commitmentAccepted"}',
      l10n: l10n,
    );

    expect(copy.headline, 'Alex accepted your ask');
    expect(copy.body, 'Garden cleanup');
  });

  test('feed row copy keeps trust excerpt after stripping request title', () {
    final copy = resolveUpdatesFeedRowCopy(
      title: 'Trust in Alex increased',
      body:
          'Move help this weekend — After the request closed, your trust shifted.',
      presentationKey: 'trust_given_changed_up',
      presentationPayloadJson:
          '{"beaconTitle":"Move help this weekend","eventType":"trustGivenChanged"}',
      l10n: l10n,
    );

    expect(copy.headline, 'Trust in Alex increased');
    expect(copy.body, 'Move help this weekend');
  });

  test('help_offer_submitted keeps personal-note excerpt as body', () {
    final withNote = resolveUpdatesFeedRowCopy(
      title: 'Vadim',
      body: 'I can sew the costume',
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      l10n: l10n,
    );
    expect(withNote.headline, 'Vadim');
    expect(withNote.body, 'I can sew the costume');

    final emptyNote = resolveUpdatesFeedRowCopy(
      title: 'Vadim',
      body: '',
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      l10n: l10n,
    );
    expect(emptyNote.headline, 'Vadim');
    expect(emptyNote.body, l10n.updatesFallbackBodyHelpOfferSubmitted);
  });

  group('review package rows', () {
    const payload = '{"beaconTitle":"Garden cleanup"}';

    test(
      'review_all_packages_in renders title and body with request title',
      () {
        final copy = resolveUpdatesReceiptDisplayCopy(
          title: '',
          body: '',
          presentationKey: 'review_all_packages_in',
          presentationPayloadJson: payload,
          l10n: l10n,
        );

        expect(copy.title, l10n.updatesFallbackTitleReviewAllIn);
        expect(
          copy.body,
          l10n.updatesFallbackBodyReviewAllIn('Garden cleanup'),
        );
      },
    );

    test(
      'review_window_cancelled renders title and body with request title',
      () {
        final copy = resolveUpdatesReceiptDisplayCopy(
          title: '',
          body: '',
          presentationKey: 'review_window_cancelled',
          presentationPayloadJson: payload,
          l10n: l10n,
        );

        expect(copy.title, l10n.updatesFallbackTitleReviewCancelled);
        expect(
          copy.body,
          l10n.updatesFallbackBodyReviewCancelled('Garden cleanup'),
        );
      },
    );

    test('without a request title the body falls back to generic', () {
      final copy = resolveUpdatesReceiptDisplayCopy(
        title: '',
        body: '',
        presentationKey: 'review_all_packages_in',
        l10n: l10n,
      );

      expect(copy.body, l10n.updatesFallbackBodyGeneric);
    });
  });
}
