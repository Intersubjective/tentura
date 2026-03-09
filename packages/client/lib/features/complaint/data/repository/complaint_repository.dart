import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import '../gql/_g/complaint_create.req.gql.dart';

@lazySingleton
class ComplaintRepository extends RemoteRepository {
  ComplaintRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<void> create({
    required String id,
    required String email,
    required String details,
    required ComplaintType type,
  }) async => (await requestDataOnlineOrThrow(
    GCreateComplaintReq(
      (b) => b.vars
        ..id = id
        ..email = email
        ..details = details
        ..type = type.name,
    ),
    label: _label,
  )).complaintCreate;

  static const _label = 'Complaint';
}
