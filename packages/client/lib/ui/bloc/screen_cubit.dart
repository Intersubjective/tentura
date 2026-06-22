import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/consts.dart';

import '../effect/ui_effect.dart';
import '../effect/ui_effect_port.dart';
import 'screen_state.dart';

export 'screen_state.dart';
export 'state_base.dart';

@singleton
class ScreenCubit extends Cubit<ScreenState> {
  /// App-wide singleton: navigation/messaging via [UiEffectPort].
  @factoryMethod
  ScreenCubit(UiEffectPort effects)
      : _effects = effects,
        _local = false,
        super(const ScreenState());

  /// Route-local bus: emits [StateIsNavigating] for nested-router listeners.
  ScreenCubit.local()
      : _effects = null,
        _local = true,
        super(const ScreenState());

  final UiEffectPort? _effects;
  final bool _local;

  void back() => _local
      ? emit(state.navigateBack())
      : _effects!.emit(const NavigateBack());

  void showGraphFor(String id) => _navigateTo('$kPathGraph/$id');

  void showForwardsGraphFor(String id) =>
      _navigateTo('$kPathForwardsGraph/$id');

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
    _navigateTo('$kPathForwardsGraph/$beaconId?$query');
  }

  void showRating() => _navigateTo(kPathRating);

  void showBeaconsOf(String id) => _navigateTo('$kPathBeaconViewAll/$id');

  void showBeaconCreate() => _navigateTo(kPathBeaconNew);

  void showBeaconEditDraft(String id) =>
      _navigateTo('$kPathBeaconNew?$kQueryBeaconDraftId=$id');

  void showBeacon(
    String id, {
    String entry = kBeaconEntryUnknown,
  }) =>
      _navigateTo(
        '$kPathBeaconView/$id?$kQueryBeaconEntry=${Uri.encodeQueryComponent(entry)}',
      );

  void showProfile(String id) => _navigateTo('$kPathProfileView/$id');

  void showProfileEditor() => _navigateTo(kPathProfileEdit);

  void showProfileCreator() => _navigateTo('$kPathSignUp/ ');

  void showSettings() => _navigateTo(kPathSettings);

  void showComplaint(String id) => _navigateTo('$kPathComplaint/$id');

  void showMessaging(LocalizableMessage message) {
    if (_local) {
      emit(state.messaging(message));
    } else {
      _effects!.emit(ShowMessage(message));
    }
  }

  void _navigateTo(String path) {
    if (_local) {
      emit(state.navigateTo(path));
    } else {
      _effects!.emit(NavigatePush(path));
    }
  }
}
