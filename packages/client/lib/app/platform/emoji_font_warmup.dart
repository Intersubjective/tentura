import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// Emoji the first screens are most likely to show: common request-title
/// emoji plus the room reaction quick picker.
final String kEmojiFontWarmupSample = [
  '\u{1F6CB}\uFE0F', // couch
  '\u{1F4E6}', // package
  '\u{1F389}', // party popper
  '\u{1F44D}', // thumbs up
  '\u{1F525}', // fire
  '\u2705', // check mark
  '\u{1F3E0}', // house
  '\u{1F697}', // car
  '\u{1F4DA}', // books
  '\u{1F331}', // seedling
  ...BeaconRoomMessageReaction.quickPickerEmojis,
].join();

/// Starts the web engine's emoji fallback font download at startup.
///
/// Flutter web fetches the Noto emoji fallback font only when it first lays
/// out an emoji, so on the JS/CanvasKit build (Firefox, Safari) the first
/// request titles painted tofu until it arrived. Laying out
/// [kEmojiFontWarmupSample] once, before the app's own startup work, puts that
/// download in flight early. No-op off the web.
void warmUpEmojiFallbackFont({
  bool isWeb = kIsWeb,
  void Function(String text)? layOut,
}) {
  if (!isWeb) return;
  try {
    (layOut ?? _layOutOffscreen)(kEmojiFontWarmupSample);
  } on Object catch (e) {
    // Best effort: the engine still downloads the font lazily.
    debugPrint('Emoji font warm-up failed: $e');
  }
}

void _layOutOffscreen(String text) =>
    (ui.ParagraphBuilder(ui.ParagraphStyle())..addText(text)).build()
      ..layout(const ui.ParagraphConstraints(width: 4096))
      ..dispose();
