/// Unique `public_key` values for parallel-safe Postgres integration tests.
///
/// Each test file must pass a stable [namespace] (e.g. the user-id prefix).
/// [slot] is 1–9 per user within that file.
String pgTestPublicKey(String namespace, int slot) {
  assert(slot >= 1 && slot <= 9, 'slot must be 1–9');
  if (namespace.isEmpty) {
    throw ArgumentError.value(namespace, 'namespace', 'must not be empty');
  }
  final ns = namespace.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final tag = ns.length >= 2 ? ns.substring(0, 2) : ns.padRight(2, 'x');
  final c1 = String.fromCharCode('a'.codeUnitAt(0) + (tag.codeUnitAt(0) % 26));
  final c2 = String.fromCharCode('a'.codeUnitAt(0) + (tag.codeUnitAt(1) % 26));
  final anchor = '$c1$c2$slot';
  final buf = StringBuffer();
  while (buf.length < 44) {
    buf.write(anchor);
  }
  return buf.toString().substring(0, 44);
}
