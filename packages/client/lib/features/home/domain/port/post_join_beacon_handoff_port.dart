import '../entity/post_join_destination.dart';

/// Reads a one-shot beacon handoff written by the static landing (web only).
abstract class PostJoinBeaconHandoffPort {
  PostJoinDestination? readAndClear();
}
