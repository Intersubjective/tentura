import 'package:freezed_annotation/freezed_annotation.dart';

part 'debug_settings_state.freezed.dart';

const kDebugSendCooldown = Duration(seconds: 10);

@freezed
abstract class DebugSettingsState with _$DebugSettingsState {
  const factory DebugSettingsState({
    @Default(true) bool isLoadingFcmInfo,
    String? fcmToken,
    String? fcmAppId,
    @Default('') String platform,
    @Default(false) bool permissionGranted,
    @Default(false) bool serverSynced,
    DateTime? fcmCooldownUntil,
    DateTime? emailCooldownUntil,
    @Default(false) bool isSendingFcm,
    @Default(false) bool isSendingEmail,
  }) = _DebugSettingsState;

  const DebugSettingsState._();

  bool get isFcmTestEnabled =>
      !isSendingFcm &&
      (fcmCooldownUntil == null || DateTime.now().isAfter(fcmCooldownUntil!));

  bool get isEmailTestEnabled =>
      !isSendingEmail &&
      (emailCooldownUntil == null ||
          DateTime.now().isAfter(emailCooldownUntil!));
}
