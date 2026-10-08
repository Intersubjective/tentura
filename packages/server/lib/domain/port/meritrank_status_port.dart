import 'package:tentura_server/domain/entity/meritrank_status.dart';

// ignore: one_member_abstracts -- injectable status port, swapped per environment
abstract class MeritrankStatusPort {
  Future<MeritrankStatus> status();
}
