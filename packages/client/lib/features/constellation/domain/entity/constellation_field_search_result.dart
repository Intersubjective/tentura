import 'package:meta/meta.dart';

@immutable
final class ConstellationFieldSearchPersonHit {
  const ConstellationFieldSearchPersonHit({
    required this.id,
    this.displayName,
    this.handle,
  });

  final String id;
  final String? displayName;
  final String? handle;
}

@immutable
final class ConstellationFieldSearchRequestHit {
  const ConstellationFieldSearchRequestHit({
    required this.id,
    required this.authorId,
    required this.title,
    required this.status,
    required this.hidden,
    required this.lastActivityAt,
  });

  final String id;
  final String authorId;
  final String title;
  final int status;
  final bool hidden;
  final DateTime lastActivityAt;
}

@immutable
final class ConstellationFieldSearchPostHit {
  const ConstellationFieldSearchPostHit({
    required this.id,
    required this.authorId,
    required this.rootExcerpt,
    required this.status,
    required this.hidden,
    required this.lastActivityAt,
    this.expiresAt,
  });

  final String id;
  final String authorId;
  final String rootExcerpt;
  final int status;
  final bool hidden;
  final DateTime lastActivityAt;
  final DateTime? expiresAt;
}

@immutable
final class ConstellationFieldSearchResult {
  const ConstellationFieldSearchResult({
    this.people = const [],
    this.requests = const [],
    this.posts = const [],
  });

  final List<ConstellationFieldSearchPersonHit> people;
  final List<ConstellationFieldSearchRequestHit> requests;
  final List<ConstellationFieldSearchPostHit> posts;

  bool get isEmpty =>
      people.isEmpty && requests.isEmpty && posts.isEmpty;
}

const emptyConstellationFieldSearchResult = ConstellationFieldSearchResult();
