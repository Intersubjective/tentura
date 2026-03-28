import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/inbox_item.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'inbox_state.freezed.dart';

@freezed
abstract class InboxState extends StateBase with _$InboxState {
  const factory InboxState({
    @Default('') String context,
    @Default([]) List<InboxItem> items,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _InboxState;

  const InboxState._();

  List<InboxItem> get needsMe =>
      items.where((e) => !e.isWatching).toList();

  List<InboxItem> get watching =>
      items.where((e) => e.isWatching).toList();
}
