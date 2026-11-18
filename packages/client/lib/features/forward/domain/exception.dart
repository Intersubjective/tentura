import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura/domain/entity/beacon.dart';

/// The server returned the target, but forwarding is unavailable.
final class ForwardPermissionDenied implements Exception {
  const ForwardPermissionDenied(this.beacon);

  final Beacon beacon;
}

sealed class ForwardException extends LocalizableException {
  const ForwardException();
}

final class IneligibleRecipientsException extends ForwardException {
  const IneligibleRecipientsException();

  @override
  String get toEn => 'Some recipients cannot receive forwards';

  @override
  String get toRu => 'Некоторые получатели не могут принять пересылку';
}
