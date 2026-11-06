/// Shapes user-authored plain text for one-line previews (e.g. Activity).
///
/// [#1109] Removes angle-bracket regions that look like pseudo-HTML or
/// script-like markup so previews do not show literal `<b>…</b>` debris.
/// Does **not** parse HTML: no execution, no entity decoding.
///
/// Preserves `<` / `>` when they are not part of a simple `<…>` region (e.g.
/// `a < b`, `->`, unicode).
String stripAngleBracketRegionsForPlainPreview(String input) {
  if (!input.contains('<')) return input;
  // Atomic angle chunks only: no nested `<` and no newline inside the region
  // (a newline breaks the fake "tag", so we leave it literal — #1109).
  final atomic = RegExp(r'<[^<\n>]{0,500}>');
  var s = input;
  for (var i = 0; i < 64; i++) {
    final next = s.replaceAll(atomic, '');
    if (next == s) break;
    s = next;
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}
