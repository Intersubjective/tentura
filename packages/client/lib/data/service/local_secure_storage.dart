import 'package:injectable/injectable.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

@singleton
class LocalSecureStorage {
  final _lock = Lock();

  @PostConstruct(preResolve: true)
  Future<void> init() => _secureStorage.read(key: 'init');

  Future<String?> read(String key) => _lock.synchronized(
    () => _secureStorage.read(key: key),
  );

  Future<void> write(String key, String? value) => _lock.synchronized(
    () => _secureStorage.write(key: key, value: value),
  );

  Future<void> delete(String key) => _lock.synchronized(
    () => _secureStorage.delete(key: key),
  );

  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
}
