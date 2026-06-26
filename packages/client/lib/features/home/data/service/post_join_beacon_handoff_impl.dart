import 'package:injectable/injectable.dart';

import '../../domain/entity/post_join_destination.dart';
import '../../domain/port/post_join_beacon_handoff_port.dart';
import 'post_join_beacon_handoff.dart';

@Singleton(as: PostJoinBeaconHandoffPort)
class PostJoinBeaconHandoff implements PostJoinBeaconHandoffPort {
  @override
  PostJoinDestination? readAndClear() => readPostJoinBeaconHandoff();
}
