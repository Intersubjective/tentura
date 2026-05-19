import 'package:freezed_annotation/freezed_annotation.dart';

part 'last_fcm_registration.freezed.dart';

@freezed
abstract class LastFcmRegistration with _$LastFcmRegistration {
  const factory LastFcmRegistration({
    required String accountId,
    required String appId,
    required String token,
  }) = _LastFcmRegistration;

  const LastFcmRegistration._();

  bool matches({
    required String accountId,
    required String appId,
    required String token,
  }) =>
      this.accountId == accountId && this.appId == appId && this.token == token;
}
