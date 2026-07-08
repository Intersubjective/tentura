import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/consts.dart';

import '../effect/ui_effect.dart';
import '../effect/ui_effect_bus.dart';
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
        super(const ScreenState());

  /// Route-local bus for screens that provide their own [UiEffectHandler].
  factory ScreenCubit.local([UiEffectPort? effects]) =>
      ScreenCubit(effects ?? UiEffectBus());

  final UiEffectPort _effects;

  UiEffectPort get effects => _effects;

  void back() => _effects.emit(const NavigateBack());

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

  void showInvolvedBeaconsOf(String id) =>
      _navigateTo('$kPathBeaconInvolvedAll/$id');

  void showBeaconCreate() => _navigateTo(kPathBeaconNew);

  void showBeaconCreateFor(String userId) => _navigateTo(
    '$kPathBeaconNew?'
    '${kQueryBeaconForwardTo}=${Uri.encodeQueryComponent(userId)}',
  );

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

  void showForwardToPerson(String id) =>
      _navigateTo('$kPathForwardPerson/$id');

  void showProfileEditor() => _navigateTo(kPathProfileEdit);

  void showProfileCreator() => _navigateTo(kPathSignUp);

  void showInviteGenealogy() => _navigateTo(kPathInviteGenealogy);

  void showInviteGenealogyWith(String id) => _navigateTo(
    '$kPathInviteGenealogy?$kQueryGenealogyWith=${Uri.encodeQueryComponent(id)}',
  );

  void showSettings() => _navigateTo(kPathSettings);

  void showComplaint(String id) => _navigateTo('$kPathComplaint/$id');

  void showAccountDeletionRequest(String profileId) => _navigateTo(
    '$kPathComplaint/$profileId?fixedType=${ComplaintType.accountDeletionRequest.name}',
  );

  void showMessaging(LocalizableMessage message) {
    _effects.emit(ShowMessage(message));
  }

  void _navigateTo(String path) => _effects.emit(NavigatePush(path));
}
