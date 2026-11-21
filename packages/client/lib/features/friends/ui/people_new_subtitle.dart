import 'package:tentura/features/friends/domain/entity/person_list_meta.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/relative_time.dart';

/// Reason line for a person in the People «New» section (#912).
String peopleNewSectionSubtitle({
  required L10n l10n,
  required PersonNewReason reason,
  required DateTime newSince,
  required DateTime now,
}) {
  final relative = compactRelativeTimeAgo(when: newSince, now: now, l10n: l10n);
  return switch (reason) {
    PersonNewReason.invite => l10n.friendsPeopleNewReasonInvite(relative),
    PersonNewReason.trusted => l10n.friendsPeopleNewReasonTrusted(relative),
    PersonNewReason.mutual => l10n.friendsPeopleNewReasonMutual(relative),
  };
}
