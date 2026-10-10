import 'package:tentura/domain/entity/likable.dart';

/// Absolute, idempotent vote writes without a follow-up profile read.
// ignore: one_member_abstracts -- narrow injectable write boundary
abstract interface class LikeWritePort {
  Future<T> setLike<T extends Likable>(T entity, {required int amount});
}
