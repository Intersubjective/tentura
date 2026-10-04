import 'dart:convert';

/// Lifecycle of a «Who'll take it?» baton (server `batonDataJson.status`).
enum RoomBatonStatus {
  collecting,
  taken,
  cancelled;

  static RoomBatonStatus? fromWire(Object? raw) => switch (raw) {
    'collecting' => collecting,
    'taken' => taken,
    'cancelled' => cancelled,
    _ => null,
  };
}

/// A candidate's answer; `waiting` means not answered yet.
enum RoomBatonResponse {
  waiting,
  canHelp,
  cantHelp;

  static RoomBatonResponse? fromWire(Object? raw) => switch (raw) {
    'waiting' => waiting,
    'can_help' => canHelp,
    'cant_help' => cantHelp,
    _ => null,
  };
}

/// How the taker was chosen; only the author sees it.
enum RoomBatonSelectionMode {
  auto,
  manual;

  static RoomBatonSelectionMode? fromWire(Object? raw) => switch (raw) {
    'auto' => auto,
    'manual' => manual,
    _ => null,
  };
}

/// What a candidate learns once the baton is final.
enum RoomBatonOutcome {
  you,
  someoneElse,
  closed;

  static RoomBatonOutcome? fromWire(Object? raw) => switch (raw) {
    'you' => you,
    'someoneElse' => someoneElse,
    'closed' => closed,
    _ => null,
  };
}

/// The selected person.
class RoomBatonTaker {
  const RoomBatonTaker({required this.id, required this.title});

  final String id;
  final String title;

  static RoomBatonTaker? _tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || id.isEmpty) return null;
    return RoomBatonTaker(id: id, title: title is String ? title : '');
  }
}

/// One asked person, as the author sees them.
class RoomBatonCandidate {
  const RoomBatonCandidate({
    required this.userId,
    required this.title,
    required this.tier,
    required this.response,
    this.respondedAt,
  });

  final String userId;
  final String title;
  final int tier;
  final RoomBatonResponse response;
  final DateTime? respondedAt;

  static RoomBatonCandidate? _tryParse(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['userId'];
    final tier = raw['tier'];
    final response = RoomBatonResponse.fromWire(raw['response']);
    if (userId is! String || userId.isEmpty) return null;
    if (tier is! num || response == null) return null;
    final title = raw['title'];
    final respondedAt = raw['respondedAt'];
    return RoomBatonCandidate(
      userId: userId,
      title: title is String ? title : '',
      tier: tier.toInt(),
      response: response,
      respondedAt: respondedAt is String
          ? DateTime.tryParse(respondedAt)?.toUtc()
          : null,
    );
  }
}

/// Per-viewer baton projection carried by `RoomMessage.baton`.
///
/// The server computes a different shape per viewer role (author, asked
/// candidate, anyone else), so each role is its own variant.
sealed class RoomBatonData {
  const RoomBatonData({required this.id, required this.status});

  final String id;
  final RoomBatonStatus status;

  /// Parses `batonDataJson`; null for absent, non-JSON or malformed input.
  /// Unknown keys are ignored.
  static RoomBatonData? tryParse(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final id = decoded['id'];
    final status = RoomBatonStatus.fromWire(decoded['status']);
    if (id is! String || id.isEmpty || status == null) return null;
    return switch (decoded['viewerRole']) {
      'author' => _parseAuthor(decoded, id, status),
      'candidate' => RoomBatonCandidateData(
        id: id,
        status: status,
        myResponse: RoomBatonResponse.fromWire(decoded['myResponse']),
        outcome: RoomBatonOutcome.fromWire(decoded['outcome']),
        taker: RoomBatonTaker._tryParse(decoded['taker']),
      ),
      'observer' => _parseObserver(decoded, id, status),
      _ => null,
    };
  }

  static RoomBatonAuthorData? _parseAuthor(
    Map<dynamic, dynamic> map,
    String id,
    RoomBatonStatus status,
  ) {
    final rawCandidates = map['candidates'];
    if (rawCandidates is! List) return null;
    final candidates = <RoomBatonCandidate>[];
    for (final raw in rawCandidates) {
      final candidate = RoomBatonCandidate._tryParse(raw);
      if (candidate == null) return null;
      candidates.add(candidate);
    }
    final allAnswered = map['allAnswered'];
    final eligibleCount = map['eligibleCount'];
    return RoomBatonAuthorData(
      id: id,
      status: status,
      candidates: candidates,
      allAnswered: allAnswered is bool && allAnswered,
      eligibleCount: eligibleCount is num ? eligibleCount.toInt() : 0,
      taker: RoomBatonTaker._tryParse(map['taker']),
      selectionMode: RoomBatonSelectionMode.fromWire(map['selectionMode']),
    );
  }

  static RoomBatonObserverData? _parseObserver(
    Map<dynamic, dynamic> map,
    String id,
    RoomBatonStatus status,
  ) {
    final taker = RoomBatonTaker._tryParse(map['taker']);
    if (taker == null) return null;
    return RoomBatonObserverData(id: id, status: status, taker: taker);
  }
}

/// The message author's view: every asked person and their answer.
class RoomBatonAuthorData extends RoomBatonData {
  const RoomBatonAuthorData({
    required super.id,
    required super.status,
    required this.candidates,
    required this.allAnswered,
    required this.eligibleCount,
    this.taker,
    this.selectionMode,
  });

  final List<RoomBatonCandidate> candidates;
  final bool allAnswered;

  /// Number of candidates currently selectable («Can help»).
  final int eligibleCount;
  final RoomBatonTaker? taker;
  final RoomBatonSelectionMode? selectionMode;
}

/// An asked person's view: only their own answer, then the outcome.
class RoomBatonCandidateData extends RoomBatonData {
  const RoomBatonCandidateData({
    required super.id,
    required super.status,
    this.myResponse,
    this.outcome,
    this.taker,
  });

  /// Null on a cancelled baton, where the answer is no longer shown.
  final RoomBatonResponse? myResponse;
  final RoomBatonOutcome? outcome;
  final RoomBatonTaker? taker;
}

/// Everyone else's view: only the taker, once selected.
class RoomBatonObserverData extends RoomBatonData {
  const RoomBatonObserverData({
    required super.id,
    required super.status,
    required this.taker,
  });

  final RoomBatonTaker taker;
}
