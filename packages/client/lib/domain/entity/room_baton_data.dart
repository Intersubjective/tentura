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

/// The viewer's named partner on a «together» answer (`myPartner` on candidate).
class RoomBatonMyPartner {
  const RoomBatonMyPartner({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;

  /// Wire: `pending`, `accepted`, or `declined`.
  final String status;

  static RoomBatonMyPartner? _tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final status = raw['status'];
    if (id is! String || id.isEmpty) return null;
    if (status is! String || status.isEmpty) return null;
    final title = raw['title'];
    return RoomBatonMyPartner(
      id: id,
      title: title is String ? title : '',
      status: status,
    );
  }
}

/// An invitation to join someone else's «together» answer.
class RoomBatonPartnerInvite {
  const RoomBatonPartnerInvite({
    required this.fromUserId,
    required this.title,
    required this.status,
  });

  final String fromUserId;
  final String title;

  /// Wire: `pending` or `accepted`.
  final String status;

  static RoomBatonPartnerInvite? _tryParse(Object? raw) {
    if (raw is! Map) return null;
    final fromUserId = raw['fromUserId'];
    final status = raw['status'];
    if (fromUserId is! String || fromUserId.isEmpty) return null;
    if (status is! String || status.isEmpty) return null;
    final title = raw['title'];
    return RoomBatonPartnerInvite(
      fromUserId: fromUserId,
      title: title is String ? title : '',
      status: status,
    );
  }
}

/// A confirmed pair in the author's collecting view.
class RoomBatonConfirmedPair {
  const RoomBatonConfirmedPair({
    required this.takerId,
    required this.partnerId,
    required this.tier,
  });

  final String takerId;
  final String partnerId;
  final int tier;

  static RoomBatonConfirmedPair? _tryParse(Object? raw) {
    if (raw is! Map) return null;
    final takerId = raw['takerId'];
    final partnerId = raw['partnerId'];
    final tier = raw['tier'];
    if (takerId is! String ||
        takerId.isEmpty ||
        partnerId is! String ||
        partnerId.isEmpty) {
      return null;
    }
    if (tier is! num) return null;
    return RoomBatonConfirmedPair(
      takerId: takerId,
      partnerId: partnerId,
      tier: tier.toInt(),
    );
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
    this.partner,
  });

  final String userId;
  final String title;
  final int tier;
  final RoomBatonResponse response;
  final DateTime? respondedAt;

  /// Set when the candidate's «together» partner is confirmed (author only).
  final RoomBatonTaker? partner;

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
      partner: RoomBatonTaker._tryParse(raw['partner']),
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

  static List<RoomBatonPartnerInvite> _parsePartnerInvites(Object? raw) {
    if (raw is! List) return const [];
    final invites = <RoomBatonPartnerInvite>[];
    for (final item in raw) {
      final invite = RoomBatonPartnerInvite._tryParse(item);
      if (invite != null) invites.add(invite);
    }
    return invites;
  }

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
      'candidate' => _parseCandidate(decoded, id, status),
      'partner' => _parsePartner(decoded, id, status),
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
    final rawPairs = map['pairs'];
    final pairs = <RoomBatonConfirmedPair>[];
    if (rawPairs is List) {
      for (final raw in rawPairs) {
        final pair = RoomBatonConfirmedPair._tryParse(raw);
        if (pair == null) return null;
        pairs.add(pair);
      }
    }
    return RoomBatonAuthorData(
      id: id,
      status: status,
      candidates: candidates,
      allAnswered: allAnswered is bool && allAnswered,
      eligibleCount: eligibleCount is num ? eligibleCount.toInt() : 0,
      taker: RoomBatonTaker._tryParse(map['taker']),
      coTaker: RoomBatonTaker._tryParse(map['coTaker']),
      selectionMode: RoomBatonSelectionMode.fromWire(map['selectionMode']),
      pairs: pairs,
    );
  }

  static RoomBatonCandidateData? _parseCandidate(
    Map<dynamic, dynamic> map,
    String id,
    RoomBatonStatus status,
  ) {
    return RoomBatonCandidateData(
      id: id,
      status: status,
      myResponse: RoomBatonResponse.fromWire(map['myResponse']),
      outcome: RoomBatonOutcome.fromWire(map['outcome']),
      taker: RoomBatonTaker._tryParse(map['taker']),
      coTaker: RoomBatonTaker._tryParse(map['coTaker']),
      myPartner: RoomBatonMyPartner._tryParse(map['myPartner']),
      partnerInvites: _parsePartnerInvites(map['partnerInvites']),
    );
  }

  static RoomBatonPartnerData? _parsePartner(
    Map<dynamic, dynamic> map,
    String id,
    RoomBatonStatus status,
  ) {
    return RoomBatonPartnerData(
      id: id,
      status: status,
      outcome: RoomBatonOutcome.fromWire(map['outcome']),
      partnerInvites: _parsePartnerInvites(map['partnerInvites']),
    );
  }

  static RoomBatonObserverData? _parseObserver(
    Map<dynamic, dynamic> map,
    String id,
    RoomBatonStatus status,
  ) {
    final taker = RoomBatonTaker._tryParse(map['taker']);
    if (status == RoomBatonStatus.taken && taker == null) return null;
    return RoomBatonObserverData(
      id: id,
      status: status,
      taker: taker,
      coTaker: RoomBatonTaker._tryParse(map['coTaker']),
    );
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
    this.coTaker,
    this.selectionMode,
    this.pairs = const [],
  });

  final List<RoomBatonCandidate> candidates;
  final bool allAnswered;

  /// Number of candidates currently selectable («Can help»).
  final int eligibleCount;
  final RoomBatonTaker? taker;
  final RoomBatonTaker? coTaker;
  final RoomBatonSelectionMode? selectionMode;
  final List<RoomBatonConfirmedPair> pairs;

  /// Whether the candidate rows carry a priority label (more than one tier).
  bool get showsTiers => candidates.map((c) => c.tier).toSet().length > 1;
}

/// An asked person's view: only their own answer, then the outcome.
class RoomBatonCandidateData extends RoomBatonData {
  const RoomBatonCandidateData({
    required super.id,
    required super.status,
    this.myResponse,
    this.outcome,
    this.taker,
    this.coTaker,
    this.myPartner,
    this.partnerInvites = const [],
  });

  /// Null on a cancelled baton, where the answer is no longer shown.
  final RoomBatonResponse? myResponse;
  final RoomBatonOutcome? outcome;
  final RoomBatonTaker? taker;
  final RoomBatonTaker? coTaker;
  final RoomBatonMyPartner? myPartner;
  final List<RoomBatonPartnerInvite> partnerInvites;
}

/// A named partner's view: invitations from asked people, then the outcome.
class RoomBatonPartnerData extends RoomBatonData {
  const RoomBatonPartnerData({
    required super.id,
    required super.status,
    this.outcome,
    this.partnerInvites = const [],
  });

  final RoomBatonOutcome? outcome;
  final List<RoomBatonPartnerInvite> partnerInvites;
}

/// Everyone else's view: that the baton exists and its status, plus the taker
/// once selected. Never who was asked or how they answered.
class RoomBatonObserverData extends RoomBatonData {
  const RoomBatonObserverData({
    required super.id,
    required super.status,
    this.taker,
    this.coTaker,
  });

  /// Set exactly when [status] is [RoomBatonStatus.taken].
  final RoomBatonTaker? taker;
  final RoomBatonTaker? coTaker;
}
