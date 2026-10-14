import 'package:tentura/features/beacon_lobby/domain/beacon_lobby_gateway.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';

/// In-memory lobby with the server's rules (U088): the author and people
/// with a live offer get in, banned people don't, only the author bans.
class FakeLobbyGateway implements BeaconLobbyGateway {
  FakeLobbyGateway({
    required this.viewerId,
    this.authorId = 'Uauthor',
    Set<String>? offerers,
  }) : offerers = offerers ?? {'Unina'};

  final String viewerId;
  final String authorId;
  final Set<String> offerers;
  final banned = <String>[];
  final messagesList = <BeaconLobbyMessage>[];
  final calls = <String>[];
  bool failNextAction = false;

  bool get _allowed =>
      viewerId == authorId ||
      (offerers.contains(viewerId) && !banned.contains(viewerId));

  @override
  Future<BeaconLobbyInfo> open(String beaconId) async {
    calls.add('open');
    if (!_allowed) throw Exception('The lobby is for people who offered help');
    return BeaconLobbyInfo(
      beaconId: beaconId,
      lobbyId: 'Llobby',
      isAuthor: viewerId == authorId,
      canPost: true,
      bannedUserIds: viewerId == authorId ? List.of(banned) : const [],
    );
  }

  @override
  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
  }) async {
    if (!_allowed) throw Exception('denied');
    return List.of(messagesList);
  }

  @override
  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  }) async {
    calls.add('post $body');
    if (failNextAction) {
      failNextAction = false;
      throw Exception('network');
    }
    messagesList.add(
      BeaconLobbyMessage(
        id: 'M${messagesList.length}',
        authorId: viewerId,
        authorName: viewerId == authorId ? 'Anna' : 'Nina',
        body: body,
      ),
    );
  }

  @override
  Future<void> ban({required String beaconId, required String userId}) async {
    calls.add('ban $userId');
    if (failNextAction) {
      failNextAction = false;
      throw Exception('network');
    }
    if (!banned.contains(userId)) banned.add(userId);
  }

  @override
  Future<void> unban({required String beaconId, required String userId}) async {
    calls.add('unban $userId');
    banned.remove(userId);
  }
}
