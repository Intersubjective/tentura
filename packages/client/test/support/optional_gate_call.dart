/// Calls [target] with the feature-gate argument `peopleTagsEnabled: [gate]`,
/// the way the people-tags surfaces take it in the rest of the app.
///
/// A surface that does not take the argument yet is called without it, i.e.
/// with the compile-time gate (off). The tests therefore run to their
/// assertions and fail there, on the missing menu entry, instead of
/// stopping on a call error before they look at anything. Once a surface
/// takes the argument the fallback is never used.
///
/// A null [gate] calls [target] as is: the surface's own default.
Object? callWithPeopleTagsGate(
  Function target, {
  required bool? gate,
  List<Object?> positional = const [],
  Map<Symbol, Object?> named = const {},
}) {
  if (gate == null) return Function.apply(target, positional, named);
  try {
    return Function.apply(target, positional, {
      ...named,
      #peopleTagsEnabled: gate,
    });
  } on NoSuchMethodError {
    return Function.apply(target, positional, named);
  }
}
