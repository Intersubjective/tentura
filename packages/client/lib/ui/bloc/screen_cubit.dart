import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/consts.dart';

import 'screen_state.dart';
import 'state_base.dart';

export 'screen_state.dart';
export 'state_base.dart';

@singleton
class ScreenCubit extends Cubit<ScreenState> {
  ScreenCubit() : super(const ScreenState());

  void back() => emit(state.navigateBack());

  // Used by deep-link /chat/:id and the chat list; not reachable from Network tab.
  void showChatWith(String id) => emit(state.navigateTo('$kPathChat/$id'));

  void showGraphFor(String id) => emit(state.navigateTo('$kPathGraph/$id'));

  void showForwardsGraphFor(String id) =>
      emit(state.navigateTo('$kPathForwardsGraph/$id'));

  /// Opens the per-committer forward path graph for [beaconId] focused on
  /// [committerId]. Optional [committerName] is forwarded so the AppBar
  /// title can include the committer's display title.
  void showCommitterForwardPathFor({
    required String beaconId,
    required String committerId,
    String? committerName,
  }) {
    final query = StringBuffer('committer=${Uri.encodeQueryComponent(committerId)}');
    if (committerName != null && committerName.isNotEmpty) {
      query
        ..write('&committerName=')
        ..write(Uri.encodeQueryComponent(committerName));
    }
    emit(state.navigateTo('$kPathForwardsGraph/$beaconId?$query'));
  }

  void showRating() => emit(state.navigateTo(kPathRating));

  void showBeaconsOf(String id) =>
      emit(state.navigateTo('$kPathBeaconViewAll/$id'));

  void showBeaconCreate() => emit(state.navigateTo(kPathBeaconNew));

  void showBeaconEditDraft(String id) =>
      emit(state.navigateTo('$kPathBeaconNew?$kQueryBeaconDraftId=$id'));

  void showBeacon(
    String id, {
    String entry = kBeaconEntryUnknown,
  }) =>
      emit(
        state.navigateTo(
          '$kPathBeaconView/$id?$kQueryBeaconEntry=${Uri.encodeQueryComponent(entry)}',
        ),
      );

  void showProfile(String id) =>
      emit(state.navigateTo('$kPathProfileView/$id'));

  void showProfileEditor() => emit(state.navigateTo(kPathProfileEdit));

  void showProfileCreator() => emit(state.navigateTo('$kPathSignUp/ '));

  void showSettings() => emit(state.navigateTo(kPathSettings));

  void showComplaint(String id) =>
      emit(state.navigateTo('$kPathComplaint/$id'));

  void showMessaging(LocalizableMessage message) =>
      emit(state.messaging(message));
}
