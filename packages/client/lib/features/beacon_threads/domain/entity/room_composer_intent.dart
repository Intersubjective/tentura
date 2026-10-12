import 'package:meta/meta.dart';

/// Text another surface puts into the discussion composer, plus what the
/// person's message that still carries it records once it is sent.
///
/// Request plan (#220): «Не успеваю → написать в обсуждении» quotes the step
/// («› Шаг 3: … — не успеваю: ») and, through [planCantMake], records the
/// «can't make it» with the message's words once it is sent.
@immutable
final class RoomComposerIntent {
  const RoomComposerIntent({required this.prefill, this.planCantMake});

  /// Placed into the composer, cursor at its end.
  final String prefill;

  /// The plan step whose «can't make it» the first sent message that still
  /// starts with [prefill] records (option `chat`); null records nothing.
  final PlanCantMakeInChat? planCantMake;

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

/// «Не успеваю» on plan step [stepId], written in the discussion; the plan
/// head the person saw was [baseRevisionSeq].
@immutable
final class PlanCantMakeInChat {
  const PlanCantMakeInChat({
    required this.stepId,
    required this.baseRevisionSeq,
  });

  final String stepId;

  final int baseRevisionSeq;
}
