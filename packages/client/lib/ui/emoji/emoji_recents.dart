import 'package:flutter/foundation.dart';

/// Recently inserted emoji, newest first, shared by every composer in the app.
///
/// Kept in memory for the app session only.
abstract final class EmojiRecents {
  static const maxLength = 24;

  static final ValueNotifier<List<String>> notifier = ValueNotifier(const []);

  static List<String> get value => notifier.value;

  static void add(String emoji) {
    notifier.value = List.unmodifiable([
      emoji,
      for (final e in notifier.value)
        if (e != emoji) e,
    ].take(maxLength));
  }

  @visibleForTesting
  static void reset() => notifier.value = const [];
}
