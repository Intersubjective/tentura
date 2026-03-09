import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/complaint_entity.dart';
import 'package:tentura_server/domain/exception.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class ComplaintRepository {
  const ComplaintRepository(this._database);

  final TenturaDb _database;

  Future<void> create(ComplaintEntity complaint) async {
    try {
      await _database.managers.complaints.create(
        (o) => o(
          id: complaint.id,
          email: complaint.email,
          userId: complaint.userId,
          details: complaint.details,
          type: Value(complaint.type),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    } on UniqueViolationException catch (_) {
      throw IdDuplicateException(
        description:
            'Complaint already exists! [ '
            'id: ${complaint.id}, userId: ${complaint.userId} ]',
      );
    } catch (_) {
      rethrow;
    }
  }
}
