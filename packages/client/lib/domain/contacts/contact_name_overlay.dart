import 'package:get_it/get_it.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';

/// Subjective profiles overlay: the viewer's private contact name for
/// [userId], or '' when none. Applied wherever a `Profile` is built from
/// wire data so every surface (lists, graph, chat authors, search) shows
/// the viewer's name. Registration-guarded so plain mapper unit tests work
/// without DI.
String contactNameOf(String userId) =>
    GetIt.I.isRegistered<ContactNameStore>()
    ? GetIt.I<ContactNameStore>().nameOf(userId) ?? ''
    : '';

/// Applies the viewer's subjective contact overlay to [profile].
Profile profileWithContactOverlay(Profile profile) {
  final overlay = contactNameOf(profile.id);
  if (overlay.isEmpty || overlay == profile.contactName) {
    return profile;
  }
  return profile.copyWith(contactName: overlay);
}
