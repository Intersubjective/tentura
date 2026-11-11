import 'package:web/web.dart' as web;

/// The secure-storage keys in localStorage, listed without decrypting them.
///
/// flutter_secure_storage_web keeps the value of `<key>` under
/// `<publicKey>.<key>` and decrypts every entry inside `readAll`, so one
/// entry it cannot decrypt fails the whole call.
Iterable<String> browserSecureStorageKeys(String publicKey) {
  final prefix = '$publicKey.';
  final storage = web.window.localStorage;
  return [
    for (var i = 0; i < storage.length; i++)
      if (storage.key(i) case final item? when item.startsWith(prefix))
        item.substring(prefix.length),
  ];
}
