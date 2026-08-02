import 'package:mockito/mockito.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';

/// In-memory block pairs for unit tests (symmetric).
class FakeUserBlockRepository extends Fake implements UserBlockRepositoryPort {
  final Set<String> _pairKeys = {};

  void blockPair(String a, String b) {
    _pairKeys.add(_key(a, b));
    _pairKeys.add(_key(b, a));
  }

  String _key(String a, String b) => '$a|$b';

  bool _isBlocked(String a, String b) => _pairKeys.contains(_key(a, b));

  @override
  Future<bool> isBlockedPair({required String a, required String b}) async =>
      _isBlocked(a, b);

  @override
  Future<Set<String>> hiddenPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async =>
      peerIds.where((p) => _isBlocked(viewerId, p)).toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
