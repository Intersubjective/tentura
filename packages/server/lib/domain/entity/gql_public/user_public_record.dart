import 'package:meta/meta.dart';

import 'image_public_record.dart';
import 'mutual_score_record.dart';
import 'user_presence_record.dart';

/// Public user projection used by `mutualFriends` and nested `user` on
/// coordination rows (same shape as Hasura `UserModel` / `gqlTypeUserPublic`).
@immutable
class UserPublicRecord {
  const UserPublicRecord({
    required this.id,
    required this.title,
    required this.description,
    this.myVote,
    this.image,
    this.scores = const [],
    this.userPresence,
  });

  final String id;
  final String title;
  final String description;
  final int? myVote;
  final ImagePublicRecord? image;
  final List<MutualScoreRecord> scores;
  final UserPresenceRecord? userPresence;
}
