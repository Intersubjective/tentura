import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/inbox_item.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'activity_offers_state.freezed.dart';

@freezed
abstract class ActivityOfferBeaconMeta with _$ActivityOfferBeaconMeta {
  const factory ActivityOfferBeaconMeta({
    required int eventTotal,
    @Default(0) int eventUnseenCount,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> eventsPreview,
    @Default(false) bool unseen,
  }) = _ActivityOfferBeaconMeta;
}

@freezed
abstract class ActivityOffersState extends StateBase with _$ActivityOffersState {
  const factory ActivityOffersState({
    @Default([]) List<InboxItem> items,
    int? totalCount,
    @Default(false) bool countLoadFailed,
    @Default(false) bool pageLoadFailed,
    @Default(true) bool hasMore,
    @Default(false) bool loadingMore,
    @Default(<String>{}) Set<String> heldBackIds,
    String? pendingMovedToStreamBeaconId,
    @Default(<String>{}) Set<String> unseenBeaconIds,
    @Default(false) bool unseenQueryComplete,
    @Default(<String, ActivityOfferBeaconMeta>{})
    Map<String, ActivityOfferBeaconMeta> eventsByBeacon,
    String? offersNextCursor,
    @Default(StateIsLoading()) StateStatus status,
  }) = _ActivityOffersState;

  const ActivityOffersState._();
}
