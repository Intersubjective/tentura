import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../constellation_visibility.dart';
import '../port/constellation_visibility_port.dart';

/// Reads and keeps what the field shows, per viewer on this device (#645).
/// A failing store never blocks the field: it then shows everything.
@lazySingleton
final class ConstellationVisibilityCase extends UseCaseBase {
  ConstellationVisibilityCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationVisibilityPort _port;

  Future<ConstellationVisibility> read({required String viewerId}) async {
    try {
      return await _port.read(viewerId: viewerId) ??
          ConstellationVisibility.all;
    } on Object catch (error) {
      logger.warning('Could not read field visibility: $error');
      return ConstellationVisibility.all;
    }
  }

  Future<void> write({
    required String viewerId,
    required ConstellationVisibility visibility,
  }) async {
    try {
      await _port.write(viewerId: viewerId, visibility: visibility);
    } on Object catch (error) {
      logger.warning('Could not keep field visibility: $error');
    }
  }
}
