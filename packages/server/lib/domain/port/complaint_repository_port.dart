import 'package:tentura_server/domain/entity/complaint_entity.dart';

abstract class ComplaintRepositoryPort {
  Future<void> create(ComplaintEntity complaint);
}
