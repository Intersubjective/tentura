import 'package:tentura_root/domain/entity/localizable.dart';

/// Shown when server rejects beacon update edit after the 1h window.
final class BeaconUpdateEditExpiredMessage extends LocalizableMessage {
  const BeaconUpdateEditExpiredMessage();

  @override
  String get toEn => 'Edit window has expired (1 hour after posting).';

  @override
  String get toRu =>
      'Срок редактирования истёк (1 час после публикации).';
}
