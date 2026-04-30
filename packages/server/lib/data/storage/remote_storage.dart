import 'dart:typed_data';
import 'package:minio/minio.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/env.dart';

@singleton
class RemoteStorage {
  RemoteStorage(this.env);

  final Env env;

  late final _remoteStorage = () {
    final parts = env.kS3Endpoint.split(':');
    final host = parts.first;
    final port = parts.length > 1 ? int.tryParse(parts.last) : null;
    return Minio(
      endPoint: host,
      port: port,
      useSSL: env.kS3UseSSL,
      accessKey: env.kS3AccessKey,
      secretKey: env.kS3SecretKey,
      pathStyle: env.kS3PathStyle,
    );
  }();

  Future<Uint8List> getObject(String path) async {
    final stream = await _remoteStorage.getObject(env.kS3Bucket, path);
    final buffer = await stream.cast<Uint8List>().fold(
      BytesBuilder(copy: false),
      (p, e) => p..add(e),
    );
    return buffer.takeBytes();
  }

  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) =>
      _remoteStorage.putObject(
        env.kS3Bucket,
        path,
        bytes,
        metadata: metadata ?? _jpegPutObjectMetadata,
      );

  Future<void> removeObject(String path) =>
      _remoteStorage.removeObject(env.kS3Bucket, path);

  Map<String, String> get _jpegPutObjectMetadata => {
    kHeaderContentType: kContentTypeJpeg,
    if (env.kS3PutObjectAclValue != null)
      'x-amz-acl': env.kS3PutObjectAclValue!,
  };
}
