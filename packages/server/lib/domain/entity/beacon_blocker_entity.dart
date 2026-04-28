import 'package:tentura_server/utils/id.dart';

/// Domain id factory for [`beacon_blocker`].
abstract final class BeaconBlockerEntity {
  static String get newId => generateId('K');
}
