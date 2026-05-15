import 'package:tentura_server/utils/id.dart';

/// Domain id factory for [`coordination_item`].
abstract final class CoordinationItemEntity {
  static String get newId => generateId('I');
}
