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
}
