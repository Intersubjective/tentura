/// A proposed id-anchored mention range supplied alongside a message body.
typedef ExplicitMentionProposal = ({String userId, int offset, int length});

/// A validated id-anchored mention range safe to persist and render.
typedef ValidatedMentionSpan = ({String userId, int offset, int length});

/// Validates explicit mention ranges without performing I/O or text searches.
///
/// Proposals are considered in order, so the first valid overlapping proposal
/// wins. Invalid proposals are deliberately dropped rather than rejecting the
/// message, matching legacy unresolved `@handle` behavior.
List<ValidatedMentionSpan> validateExplicitMentionSpans({
  required String body,
  required List<ExplicitMentionProposal> proposals,
  required Set<String> Function(String userId) acceptableTokensForUserId,
}) {
  final consumed = <({int start, int end})>[];
  final out = <ValidatedMentionSpan>[];
  for (final proposal in proposals) {
    final end = proposal.offset + proposal.length;
    if (proposal.offset < 0 || proposal.length <= 0 || end > body.length) {
      continue;
    }
    if (consumed.any(
      (range) => proposal.offset < range.end && end > range.start,
    )) {
      continue;
    }
    final acceptable = acceptableTokensForUserId(proposal.userId);
    if (acceptable.isEmpty) continue;
    final candidate = body.substring(proposal.offset, end).trim().toLowerCase();
    if (!acceptable.any((token) => token.trim().toLowerCase() == candidate)) {
      continue;
    }
    consumed.add((start: proposal.offset, end: end));
    out.add((
      userId: proposal.userId,
      offset: proposal.offset,
      length: proposal.length,
    ));
  }
  return out;
}

/// Carries stored spans through a plain-text edit without re-resolving their
/// historical display tokens. Spans wholly before the edit survive unchanged,
/// spans wholly after it shift by the edit delta, and overlapping spans drop.
/// Identical text is never searched or used to infer recipient identity.
///
/// This is intentionally structural. Admission is rechecked by the caller,
/// but a later display-name/handle change must not erase an untouched stored
/// mention from message history.
List<ValidatedMentionSpan> shiftMentionSpansThroughTextEdit({
  required String oldBody,
  required String newBody,
  required List<ValidatedMentionSpan> spans,
}) {
  var prefix = 0;
  final shortest = oldBody.length < newBody.length
      ? oldBody.length
      : newBody.length;
  while (prefix < shortest && oldBody[prefix] == newBody[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < shortest - prefix &&
      oldBody[oldBody.length - 1 - suffix] ==
          newBody[newBody.length - 1 - suffix]) {
    suffix++;
  }
  final oldEditEnd = oldBody.length - suffix;
  final isInsertion = oldEditEnd == prefix;
  final delta = newBody.length - oldBody.length;
  final shifted = <ValidatedMentionSpan>[];
  for (final span in spans) {
    final end = span.offset + span.length;
    if (span.offset < 0 || span.length <= 0 || end > oldBody.length) {
      continue;
    }
    // Equality is normally safe for half-open ranges. It is ambiguous only
    // when the exact token repeats beyond the common boundary: plain edit
    // requests do not carry a selection delta that could identify which copy
    // was deleted, so drop rather than transfer identity.
    final token = oldBody.substring(span.offset, end);
    final ambiguousBeforeBoundary =
        !isInsertion && end == prefix && oldBody.indexOf(token, end) >= 0;
    final ambiguousAfterBoundary =
        !isInsertion &&
        span.offset == oldEditEnd &&
        oldBody.lastIndexOf(token, span.offset - 1) >= 0;
    if (end <= prefix && !ambiguousBeforeBoundary) {
      shifted.add(span);
    } else if (span.offset >= oldEditEnd && !ambiguousAfterBoundary) {
      shifted.add((
        userId: span.userId,
        offset: span.offset + delta,
        length: span.length,
      ));
    }
  }
  return shifted;
}
