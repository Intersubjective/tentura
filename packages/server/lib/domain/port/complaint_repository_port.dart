import 'package:tentura_server/domain/entity/complaint_entity.dart';

// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract class ComplaintRepositoryPort {
  Future<void> create(ComplaintEntity complaint);
}
