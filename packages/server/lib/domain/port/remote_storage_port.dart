import 'dart:typed_data';

abstract class RemoteStoragePort {
  Future<Uint8List> getObject(String path);

  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  });

  Future<void> removeObject(String path);
}
