import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'room_state.freezed.dart';

@freezed
abstract class RoomState extends StateBase with _$RoomState {
  const factory RoomState({
    @Default('') String beaconId,
    @Default(<RoomMessage>[]) List<RoomMessage> messages,
    @Default(<BeaconParticipant>[]) List<BeaconParticipant> participants,
    @Default(<BeaconFactCard>[]) List<BeaconFactCard> factCards,
    BeaconRoomState? roomState,
    @Default(StateIsSuccess()) StateStatus status,
    String? scrollToMessageId,
    String? pendingFactsFocusFactId,
  }) = _RoomState;

  const RoomState._();
}
