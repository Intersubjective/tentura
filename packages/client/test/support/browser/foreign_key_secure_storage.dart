// Browser-only helper: puts secure-storage entries into localStorage that
// were encrypted under a different AES key than the one this origin now
// uses — the state two tabs leave behind when each generated its own key.
// Reading such an entry makes WebCrypto reject with a DOMException
// 'OperationError'.
//
// This pins two facts of flutter_secure_storage_web (2.1.1, the version the
// client resolves) with default WebOptions:
//   * the AES key is kept in localStorage under [kSecureStorageKeyItem]
//     ('FlutterSecureStorage', WebOptions.publicKey) and is generated on the
//     first write when that item is missing;
//   * a value for `<key>` is kept under `FlutterSecureStorage.<key>`.
// [writeUnderForeignKey] checks both after writing and fails with a clear
// message if the plugin's layout changes, instead of producing an entry that
// silently decrypts.
import 'package:web/web.dart' as web;

import 'package:tentura/data/service/local_secure_storage.dart';

const kSecureStorageKeyItem = 'FlutterSecureStorage';

/// The localStorage item that holds the secure-storage value of [key].
String secureStorageItem(String key) => '$kSecureStorageKeyItem.$key';

web.Storage get _localStorage => web.window.localStorage;

/// Writes [entries] through the real [LocalSecureStorage] under a throwaway
/// AES key, then restores this origin's own key (or lets it generate a new
/// one), so the entries no longer decrypt. Other secure-storage values stay
/// readable. Returns the raw localStorage item value per key.
Future<Map<String, String>> writeUnderForeignKey(
  Map<String, String> entries,
) async {
  final ownKey = _localStorage.getItem(kSecureStorageKeyItem);
  _localStorage.removeItem(kSecureStorageKeyItem);

  final storage = LocalSecureStorage();
  final ciphertexts = <String, String>{};
  for (final MapEntry(:key, :value) in entries.entries) {
    await storage.write(key, value);
    final raw = _localStorage.getItem(secureStorageItem(key));
    if (raw == null || raw == value) {
      throw StateError(
        'flutter_secure_storage_web no longer stores "$key" encrypted under '
        '${secureStorageItem(key)}; update this helper',
      );
    }
    ciphertexts[key] = raw;
  }
  final foreignKey = _localStorage.getItem(kSecureStorageKeyItem);
  if (foreignKey == null) {
    throw StateError(
      'flutter_secure_storage_web no longer keeps its AES key under '
      '"$kSecureStorageKeyItem"; update this helper',
    );
  }

  if (ownKey != null) {
    _localStorage.setItem(kSecureStorageKeyItem, ownKey);
  } else {
    // No key yet on this origin: make the plugin generate a fresh one.
    _localStorage.removeItem(kSecureStorageKeyItem);
    await storage.write('__foreign_key_probe', 'x');
    await storage.delete('__foreign_key_probe');
  }
  if (_localStorage.getItem(kSecureStorageKeyItem) == foreignKey) {
    throw StateError('the AES key did not change; entries would decrypt');
  }
  ciphertexts.forEach(
    (key, raw) => _localStorage.setItem(secureStorageItem(key), raw),
  );
  return ciphertexts;
}

/// Removes every secure-storage item (the AES key and all values).
void clearSecureStorageItems() {
  final keys = [
    for (var i = 0; i < _localStorage.length; i++) _localStorage.key(i) ?? '',
  ];
  for (final key in keys) {
    if (key == kSecureStorageKeyItem ||
        key.startsWith('$kSecureStorageKeyItem.')) {
      _localStorage.removeItem(key);
    }
  }
}

/// The raw localStorage value of the secure-storage item for [key].
String? rawSecureStorageItem(String key) =>
    _localStorage.getItem(secureStorageItem(key));
