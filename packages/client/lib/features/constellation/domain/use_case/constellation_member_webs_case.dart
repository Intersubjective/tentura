import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/constellation_field.dart';
import '../port/constellation_member_webs_port.dart';

@lazySingleton
final class ConstellationMemberWebsCase extends UseCaseBase {
  ConstellationMemberWebsCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationMemberWebsPort _port;

  Future<List<ConstellationMemberWeb>> fetch(String beaconId) =>
      _port.fetch(beaconId);
}
