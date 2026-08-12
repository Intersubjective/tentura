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
///
/// Dart's native `int` is a fixed 64-bit two's-complement value, so a hash
/// with the sign bit set is a *negative* Dart int — `& 0xFFFFFFFFFFFFFFFF`
/// is a no-op (that mask equals -1) and `%` on a negative int still computes
/// Euclidean mod of the *signed* value, which disagrees with the true
/// unsigned-64-bit mod for roughly half of all inputs. `BigInt.toUnsigned`
/// has room to represent values up to 2^64-1 and reinterprets the bit
/// pattern correctly, which a fixed-width native `int` cannot.
int fnv1a64Mod(String input, int modulus) {
  if (modulus <= 0) {
    throw ArgumentError.value(modulus, 'modulus', 'must be positive');
  }
  final unsigned = BigInt.from(fnv1a64(input)).toUnsigned(64);
  return unsigned.remainder(BigInt.from(modulus)).toInt();
}
