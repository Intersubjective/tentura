import 'package:meta/meta.dart';

/// Text another surface puts into the discussion composer, plus what happens
/// when the person sends a message that still carries it.
///
/// Request plan (#220): «Не успеваю → написать в обсуждении» quotes the step
/// («› Шаг 3: … — не успеваю: ») and records the «can't make it» with the
/// message's words once it is sent.
@immutable
final class RoomComposerIntent {
  const RoomComposerIntent({required this.prefill, this.onSent});

  /// Placed into the composer, cursor at its end.
  final String prefill;

  /// Called once, with the trimmed sent body, for the first sent message
  /// that still starts with [prefill].
  final Future<void> Function(String body)? onSent;

  /// Whether [body] (trimmed, as sent) is the message this intent waits for.
  bool matches(String body) {
    final head = prefill.trim();
    return head.isNotEmpty && body.trim().startsWith(head);
  }

  /// [body] without the quoted prefix: the person's own words, or the whole
  /// body when they added none.
  String wordsOf(String body) {
    final trimmed = body.trim();
    final head = prefill.trim();
    if (!trimmed.startsWith(head)) return trimmed;
    final rest = trimmed.substring(head.length).trim();
    return rest.isEmpty ? trimmed : rest;
  }
}
