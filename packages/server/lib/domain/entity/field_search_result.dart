/// Lightweight Field search projections; these are not new content entities.
typedef FieldSearchPerson = ({
  String id,
  String? displayName,
  String? handle,
});

typedef FieldSearchRequestHit = ({
  String id,
  String authorId,
  String title,
  int status,
  bool hidden,
  DateTime lastActivityAt,
});

typedef FieldSearchPostHit = ({
  String id,
  String authorId,
  String rootExcerpt,
  int status,
  bool hidden,
  DateTime lastActivityAt,
  DateTime? expiresAt,
});

typedef FieldSearchResult = ({
  List<FieldSearchPerson> people,
  List<FieldSearchRequestHit> requests,
  List<FieldSearchPostHit> posts,
});

const emptyFieldSearchResult = (
  people: <FieldSearchPerson>[],
  requests: <FieldSearchRequestHit>[],
  posts: <FieldSearchPostHit>[],
);
