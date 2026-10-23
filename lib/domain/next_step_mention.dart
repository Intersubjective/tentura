/// #516 — does a Request's next step name this person?
///
/// The next step is free text ("Omar: dolly, Nina: van 9:45"), so a person is
/// "named" when their whole display name, its first word, or their @handle
/// appears in it as a whole word, ignoring case. One rule for the server
/// (the author's "left — the next step names them" update) and the client
/// (the flag on the next step itself), so the two never disagree.
///
/// A first word shorter than two letters is ignored: "A" or "J." would match
/// half the lines anyone writes.
bool nextStepMentionsPerson(
  String nextStep, {
  required String displayName,
  String handle = '',
}) {
  final line = nextStep.trim();
  if (line.isEmpty) return false;
  final name = displayName.trim();
  final first = name.split(RegExp(r'\s+')).first;
  final bareHandle = handle.trim().replaceFirst(RegExp('^@'), '');
  final candidates = <String>{
    if (name.isNotEmpty) name,
    if (_letterCount(first) >= 2) first,
    // Only as a mention: a handle like `van` is also an ordinary word.
    if (bareHandle.isNotEmpty) '@$bareHandle',
  };
  for (final candidate in candidates) {
    final pattern = RegExp(
      '(?<![\\p{L}\\p{N}_])${RegExp.escape(candidate)}(?![\\p{L}\\p{N}_])',
      caseSensitive: false,
      unicode: true,
    );
    if (pattern.hasMatch(line)) return true;
  }
  return false;
}

int _letterCount(String word) =>
    RegExp(r'\p{L}', unicode: true).allMatches(word).length;
