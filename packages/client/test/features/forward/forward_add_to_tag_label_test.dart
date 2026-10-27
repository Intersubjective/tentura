import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  test('RU «add to tag» action reads «В тег…» like the l10n string', () {
    const message = ForwardLocationMyWorkAddToTagMessage(
      beaconId: 'B1',
      recipientIds: ['U1', 'U2'],
      recipientNames: 'A, B',
    );
    expect(message.label.toRu, 'В тег…');
    expect(message.label.toRu, L10nRu().peopleTagsAddToTag);
  });

  test('RU routing-mute title spells «теги»', () {
    expect(L10nRu().settingsRoutingMute, startsWith('Теги'));
  });
}
