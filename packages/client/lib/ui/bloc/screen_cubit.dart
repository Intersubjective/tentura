import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';

import 'state_base.dart';

export 'state_base.dart';

@singleton
class ScreenCubit extends Cubit<ScreenState> {
  ScreenCubit() : super(const ScreenState());

  void back() => emit(state.navigateBack());

  void showChatWith(String id) => emit(state.navigateTo('$kPathChat/$id'));

  void showGraphFor(String id) => emit(state.navigateTo('$kPathGraph/$id'));

  void showRating() => emit(state.navigateTo(kPathRating));

  void showBeaconsOf(String id) =>
      emit(state.navigateTo('$kPathBeaconViewAll/$id'));

  void showBeaconCreate() => emit(state.navigateTo(kPathBeaconNew));

  void showBeacon(String id) => emit(state.navigateTo('$kPathBeaconView/$id'));

  void showProfile(String id) =>
      emit(state.navigateTo('$kPathProfileView/$id'));

  void showProfileEditor() => emit(state.navigateTo(kPathProfileEdit));

  void showProfileCreator() => emit(state.navigateTo('$kPathSignUp/ '));

  void showSettings() => emit(state.navigateTo(kPathSettings));

  void showComplaint(String id) =>
      emit(state.navigateTo('$kPathComplaint/$id'));

  void showInvitations() => emit(state.navigateTo(kPathInvitations));
}

class ScreenState extends StateBase {
  const ScreenState({super.status});

  ScreenState navigateTo(String path) =>
      ScreenState(status: StateIsNavigating(path));

  ScreenState navigateBack() =>
      const ScreenState(status: StateIsNavigating.back);
}
