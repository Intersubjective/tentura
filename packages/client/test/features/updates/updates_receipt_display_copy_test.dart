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

    expect(copy.headline, 'Garden cleanup');
    expect(copy.body, 'Alex accepted your ask: Bring tools');
  });

  test('feed row copy keeps trust excerpt after stripping request title', () {
    final copy = resolveUpdatesFeedRowCopy(
      title: 'Trust in Alex increased',
      body: 'Move help this weekend — After the request closed, your trust shifted.',
      presentationKey: 'trust_given_changed_up',
      presentationPayloadJson:
          '{"beaconTitle":"Move help this weekend","eventType":"trustGivenChanged"}',
      l10n: l10n,
    );

    expect(copy.headline, 'Move help this weekend');
    expect(
      copy.body,
      'Trust in Alex increased: After the request closed, your trust shifted.',
    );
  });
}
