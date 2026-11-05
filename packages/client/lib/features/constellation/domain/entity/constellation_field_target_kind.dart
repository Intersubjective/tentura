import 'constellation_field.dart';

/// Wire values for `fieldHide` / `fieldUnhide` (server `FieldTargetKind`).
enum ConstellationFieldTargetKind {
  request(0),
  post(1);

  const ConstellationFieldTargetKind(this.wireValue);

  final int wireValue;

  static ConstellationFieldTargetKind forBeaconId(
    ConstellationField field,
    String beaconId,
  ) {
    if (field.posts.any((p) => p.id == beaconId)) {
      return ConstellationFieldTargetKind.post;
    }
    return ConstellationFieldTargetKind.request;
  }
}
