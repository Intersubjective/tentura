import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_catch_up.freezed.dart';

enum RealtimeCatchUpReason {
  webSocketReconnected,
  pongTimeout,
  appResumed,
  webVisibilityRestored,
  pgListenerRecovered,
  serverRequested,
  manual,
}

@freezed
abstract class RealtimeCatchUp with _$RealtimeCatchUp {
  const factory RealtimeCatchUp({
    required String accountId,
    required int connectionEpoch,
    required RealtimeCatchUpReason reason,
  }) = _RealtimeCatchUp;

  const RealtimeCatchUp._();

  bool get shouldJitter => reason == RealtimeCatchUpReason.pgListenerRecovered;
}
