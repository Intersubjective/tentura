import 'package:freezed_annotation/freezed_annotation.dart';

part 'coordination_item_message.freezed.dart';

@freezed
abstract class CoordinationItemMessage with _$CoordinationItemMessage {
  const factory CoordinationItemMessage({
    required String id,
    required String itemId,
    required String beaconId,
    required String senderId,
    required DateTime createdAt,
    @Default('') String body,
    DateTime? editedAt,
  }) = _CoordinationItemMessage;

  const CoordinationItemMessage._();

  static final empty = CoordinationItemMessage(
    id: '',
    itemId: '',
    beaconId: '',
    senderId: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
