import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/domain/port/complaint_repository_port.dart';

import '../entity/complaint_entity.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class ComplaintCase extends UseCaseBase {
  ComplaintCase(
    this._complaintRepository, {
    required super.env,
    required super.logger,
  });

  final ComplaintRepositoryPort _complaintRepository;

  Future<bool> create({
    required String id,
    required String type,
    required String email,
    required String userId,
    required String details,
  }) async {
    try {
      await _complaintRepository.create(
        ComplaintEntity(
          id: id,
          type: ComplaintType.values.firstWhere(
            (e) => e.name == type,
            orElse: () => ComplaintType.unknown,
          ),
          email: email,
          userId: userId,
          details: details,
          createdAt: DateTime.timestamp(),
        ),
      );
      return true;
    } catch (e) {
      print(e);
      rethrow;
    }
  }
}
