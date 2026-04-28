import 'package:tentura_server/utils/id.dart';

/// Domain id factory for [`beacon_activity_event`].
abstract final class BeaconActivityEventEntity {
  static String get newId => generateId('V');
}
