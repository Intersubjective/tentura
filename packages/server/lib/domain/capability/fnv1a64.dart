import 'dart:convert';

/// FNV-1a 64-bit hash (architecture §9 exploration rotation).
///
/// Processes UTF-8 bytes left-to-right with standard constants:
/// offset basis `0xcbf29ce484222325`, prime `0x100000001b3`.
int fnv1a64(String input) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;

  var hash = offsetBasis;
  for (final byte in utf8.encode(input)) {
    hash = (hash ^ byte) & mask;
    hash = (hash * prime) & mask;
  }
  return hash;
}

/// Unsigned 64-bit modulus for exploration pool offset (§9).
int fnv1a64Mod(String input, int modulus) {
  if (modulus <= 0) {
    throw ArgumentError.value(modulus, 'modulus', 'must be positive');
  }
  const mask = 0xFFFFFFFFFFFFFFFF;
  final unsigned = fnv1a64(input) & mask;
  return unsigned % modulus;
}
