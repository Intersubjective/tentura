import 'package:tentura_server/utils/id.dart';

/// Domain id factory for [`coordination_item_message`].
abstract final class CoordinationItemMessageEntity {
  static String get newId => generateId('J');
}
