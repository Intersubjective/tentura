import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/data/repository/complaint_repository.dart';

import '../entity/complaint_entity.dart';

@Injectable(order: 2)
class ComplaintCase {
  ComplaintCase(this._complaintRepository);

  final ComplaintRepository _complaintRepository;

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
