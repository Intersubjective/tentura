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

  void showGraphFor(String id) => emit(state.navigateTo('$kPathGraph/$id'));

  void showForwardsGraphFor(String id) =>
      emit(state.navigateTo('$kPathForwardsGraph/$id'));

  /// Opens the per-help-offerer forward path graph for [beaconId] focused on
  /// [helpOffererId]. Optional [helpOffererName] is forwarded so the AppBar
  /// title can include the help offerer's display title.
  void showHelpOffererForwardPathFor({
    required String beaconId,
    required String helpOffererId,
    String? helpOffererName,
  }) {
    final query = StringBuffer('committer=${Uri.encodeQueryComponent(helpOffererId)}');
    if (helpOffererName != null && helpOffererName.isNotEmpty) {
      query
        ..write('&committerName=')
        ..write(Uri.encodeQueryComponent(helpOffererName));
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
