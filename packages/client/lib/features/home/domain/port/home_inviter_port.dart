import 'package:tentura/domain/entity/profile.dart';

/// Who invited the signed-in person, for the first-run panel (#523).
// ignore: one_member_abstracts -- injectable boundary with a test replacement
abstract class HomeInviterPort {
  /// The direct inviter, or null when there is none (a root account) or the
  /// inviter's account is gone.
  Future<Profile?> fetchMyInviter();
}
