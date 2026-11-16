import 'package:minio/minio.dart';
import 'package:minio/models.dart' as s3;

/// The error MinIO raises when the requested object does not exist.
MinioS3Error noSuchKeyError([String key = 'missing']) =>
    MinioS3Error('The specified key does not exist.', s3.Error('NoSuchKey', key, 'The specified key does not exist.', null));

/// A MinIO error carrying S3 error [code].
MinioS3Error s3CodeError(String code) =>
    MinioS3Error(code, s3.Error(code, 'k', code, null));
