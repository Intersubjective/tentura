import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/emoji_font_warmup.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// #410: on the JS/CanvasKit web build the emoji fallback font was fetched
/// only when the first emoji title painted, so titles showed tofu.
void main() {
  group('warmUpEmojiFallbackFont', () {
    test('on web lays out emoji from titles and the reaction picker once', () {
      final laidOut = <String>[];
      warmUpEmojiFallbackFont(isWeb: true, layOut: laidOut.add);

      expect(laidOut, hasLength(1));
      final text = laidOut.single;
      expect(text, contains('\u{1F6CB}')); // couch, from the issue
      expect(text, contains('\u{1F4E6}')); // package, from the issue
      for (final emoji in BeaconRoomMessageReaction.quickPickerEmojis) {
        expect(text, contains(emoji));
      }
    });

    test('does nothing off the web', () {
      final laidOut = <String>[];
      warmUpEmojiFallbackFont(isWeb: false, layOut: laidOut.add);
      expect(laidOut, isEmpty);
    });

    test('a failing layout does not break startup', () {
      expect(
        () => warmUpEmojiFallbackFont(
          isWeb: true,
          layOut: (_) => throw StateError('no engine'),
        ),
        returnsNormally,
      );
    });

    test('default layout runs against the real text engine', () {
      expect(() => warmUpEmojiFallbackFont(isWeb: true), returnsNormally);
    });
  });
}
