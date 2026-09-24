import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_seen_peer.freezed.dart';

@freezed
abstract class RealtimeSeenPeer with _$RealtimeSeenPeer {
  const factory RealtimeSeenPeer({
    required String userId,
    required DateTime lastSeenAt,
  }) = _RealtimeSeenPeer;
}
