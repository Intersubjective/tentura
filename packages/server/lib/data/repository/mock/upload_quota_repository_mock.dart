import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';

@Injectable(
  as: UploadQuotaRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UploadQuotaRepositoryMock implements UploadQuotaRepositoryPort {
  const UploadQuotaRepositoryMock();

  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      true;

  @override
  Future<int> usedBytesToday(String userId) async => 0;
}
