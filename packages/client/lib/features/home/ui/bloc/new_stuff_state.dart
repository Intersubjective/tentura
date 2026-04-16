import 'package:tentura/ui/bloc/state_base.dart';

part 'new_stuff_state.freezed.dart';

@freezed
abstract class NewStuffState extends StateBase with _$NewStuffState {
  const factory NewStuffState({
    /// Drift-persisted epoch ms; null until user has marked Inbox seen at least once.
    int? inboxLastSeenMs,
    /// Drift-persisted epoch ms; null until user has marked My Work seen at least once.
    int? myWorkLastSeenMs,
    /// Max activity epoch ms from last successful Inbox fetch; null until first report.
    int? maxInboxActivityMs,
    /// Max activity epoch ms from last successful My Work fetch; null until first report.
    int? maxMyWorkActivityMs,
    /// Home bottom nav index: 0 Inbox, 1 My Work, 2 Friends, 3 Profile.
    @Default(0) int activeHomeTabIndex,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _NewStuffState;

  const NewStuffState._();
}
