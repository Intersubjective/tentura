import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../port/constellation_field_hide_port.dart';

@lazySingleton
final class ConstellationFieldHideCase extends UseCaseBase {
  ConstellationFieldHideCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationFieldHidePort _port;

  Future<void> hide({
    required int targetKind,
    required String targetId,
  }) =>
      _port.hide(targetKind: targetKind, targetId: targetId);

  Future<void> unhide({
    required int targetKind,
    required String targetId,
  }) =>
      _port.unhide(targetKind: targetKind, targetId: targetId);
}
