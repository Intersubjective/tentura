import 'package:injectable/injectable.dart';

import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

/// Orchestrates the optional setup attached to a new-account invite receipt.
abstract interface class InviteAcceptedSetupPort {
  Future<Profile> fetchProfile(String subjectId);

  Future<InviteSeedPromptState> fetchPrompt(String subjectId);

  Future<void> rename({
    required String subjectId,
    required String privateName,
  });

  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  });

  Future<void> skip(String subjectId);
}

/// Production implementation of the invite-accepted setup boundary.
@singleton
final class InviteAcceptedSetupCase implements InviteAcceptedSetupPort {
  InviteAcceptedSetupCase(
    this._profiles,
    this._capabilities,
    this._contacts,
  );

  final ProfileRepositoryPort _profiles;
  final CapabilityRepositoryPort _capabilities;
  final ContactsCase _contacts;

  @override
  Future<Profile> fetchProfile(String subjectId) async {
    final profile = await _profiles.fetchById(subjectId);
    final privateName = _contacts.nameOf(subjectId);
    return privateName == null
        ? profile
        : profile.copyWith(contactName: privateName);
  }

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) =>
      _capabilities.fetchInviteSeedPromptState(subjectId);

  @override
  Future<void> rename({
    required String subjectId,
    required String privateName,
  }) => _contacts.rename(
    subjectId: subjectId,
    contactName: privateName,
  );

  @override
  Future<void> answer({
    required String subjectId,
    required List<String> slugs,
  }) => _capabilities.inviteSeedPromptAnswer(
    subjectId: subjectId,
    slugs: slugs,
  );

  @override
  Future<void> skip(String subjectId) =>
      _capabilities.inviteSeedPromptSkip(subjectId);
}
