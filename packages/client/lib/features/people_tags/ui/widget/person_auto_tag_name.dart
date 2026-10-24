import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

/// The user-facing name of the automatic tag [kind].
String personAutoTagName(L10n l10n, int kind) =>
    switch (PersonAutoTagKind.fromSmallint(kind)) {
      PersonAutoTagKind.mutualContact => l10n.constellationAutoTagMutualContact,
      PersonAutoTagKind.iTrust => l10n.constellationAutoTagITrust,
      PersonAutoTagKind.trustsMe => l10n.constellationAutoTagTrustsMe,
      PersonAutoTagKind.helpedMe => l10n.peopleTagsAutoHelpedMe,
      PersonAutoTagKind.iHelped => l10n.peopleTagsAutoIHelped,
      PersonAutoTagKind.workedTogether => l10n.peopleTagsAutoWorkedTogether,
      PersonAutoTagKind.invited => l10n.peopleTagsAutoInvited,
      PersonAutoTagKind.forwarded => l10n.peopleTagsAutoForwarded,
      PersonAutoTagKind.newOnField => l10n.peopleTagsAutoNewOnField,
    };
