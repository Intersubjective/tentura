import 'package:injectable/injectable.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/app/boot_step.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_keys.dart';

/// Secure storage that never lets an unreadable entry crash the caller.
///
/// An entry can stop decrypting (on web: two tabs each generated their own
/// AES key, and WebCrypto rejects with a DOMException, which is not a Dart
/// Exception). Such an entry reads as absent and is reported to Sentry once
/// per read. It is never deleted or rewritten here: it may hold a seed.
@singleton
class LocalSecureStorage {
  final _lock = Lock();

  @PostConstruct(preResolve: true)
  Future<void> init() => bootStep('secure_storage', () => read('init'));

  /// The value of [key], or null when it is absent or cannot be decrypted.
  Future<String?> read(String key) => _lock.synchronized(() => _read(key));

  /// Every entry that can be decrypted; the others are left out.
  Future<Map<String, String>> readAll() => _lock.synchronized(() async {
    final entries = <String, String>{};
    for (final key in await _storedKeys()) {
      if (await _read(key) case final value?) {
        entries[key] = value;
      }
    }
    return entries;
  });

  /// Whether [key] holds a value, readable or not.
  Future<bool> containsKey(String key) =>
      _lock.synchronized(() => _secureStorage.containsKey(key: key));

  Future<void> write(String key, String? value) => _lock.synchronized(
    () => _secureStorage.write(key: key, value: value),
  );

  Future<void> delete(String key) => _lock.synchronized(
    () => _secureStorage.delete(key: key),
  );

  Future<Iterable<String>> _storedKeys() async =>
      browserSecureStorageKeys(_secureStorage.webOptions.publicKey) ??
      (await _secureStorage.readAll()).keys;

  Future<String?> _read(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on Object catch (error, stackTrace) {
      // Only the key category leaves the device: keys carry account ids.
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) async {
          await scope.setUser(null);
          await scope.clearBreadcrumbs();
          await scope.setTag(_keyCategoryTag, _keyCategory(key));
        },
      );
      return null;
    }
  }

  static const _keyCategoryTag = 'storage_key_category';

  /// account | session_marker | beacon_command | other.
  static String _keyCategory(String key) => switch (key) {
    _ when key.startsWith('Auth:Id:') => 'account',
    _ when key.startsWith('Auth:Session:') => 'session_marker',
    'beacon_create_op' => 'beacon_command',
    _ when key.startsWith('beacon_child_cmd:') => 'beacon_command',
    _ => 'other',
  };

  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
}
