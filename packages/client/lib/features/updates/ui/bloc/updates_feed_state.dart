import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'updates_feed_state.freezed.dart';

@freezed
abstract class UpdatesFeedState extends StateBase with _$UpdatesFeedState {
  const factory UpdatesFeedState({
    @Default(AttentionView.all) AttentionView view,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> items,
    @Default(false) bool hasNextPage,
    @Default(StateIsLoading()) StateStatus status,
  }) = _UpdatesFeedState;

  const UpdatesFeedState._();

  bool get isEmpty => items.isEmpty;
}
