import 'package:freezed_annotation/freezed_annotation.dart';

part 'last_fcm_registration.freezed.dart';

@freezed
abstract class LastFcmRegistration with _$LastFcmRegistration {
  const factory LastFcmRegistration({
    required String accountId,
    required String appId,
    required String token,
    // Null for records written before this field existed, or wherever we
    // want a record treated as maximally stale — see [isStaleAt].
    DateTime? registeredAt,
  }) = _LastFcmRegistration;

  const LastFcmRegistration._();

  bool matches({
    required String accountId,
    required String appId,
    required String token,
  }) =>
      this.accountId == accountId && this.appId == appId && this.token == token;

  /// Whether this record is old enough that we should re-confirm with the
  /// server even if [matches] — our only defense against the server having
  /// silently lost the row (a past write failure, a credential rotation, a
  /// prune job, ...) with nothing on the client ever changing again.
  /// A null [registeredAt] (record predates this field) is always stale.
  bool isStaleAt(DateTime now, Duration maxAge) {
    final at = registeredAt;
    return at == null || now.difference(at) > maxAge;
  }
}
