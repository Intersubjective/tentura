import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/user_contact_entity.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';

import '../exception.dart';
import '_use_case_base.dart';

/// Subjective profiles: per-viewer private contact names.
@Injectable(order: 2)
final class ContactCase extends UseCaseBase {
  ContactCase(
    this._contactRepository, {
    required super.env,
    required super.logger,
  });

  final UserContactRepositoryPort _contactRepository;

  /// Validates and trims a contact / invite addressee name.
  static String normalizeName(String name) {
    final trimmed = name.trim();
    if (trimmed.length < kTitleMinLength || trimmed.length > kTitleMaxLength) {
      throw const IdWrongException(
        description:
            'Contact name must be $kTitleMinLength–$kTitleMaxLength '
            'characters long',
      );
    }
    return trimmed;
  }

  Future<void> set({
    required String viewerId,
    required String subjectId,
    required String contactName,
  }) async {
    if (viewerId == subjectId) {
      throw const IdWrongException(description: 'Cannot rename yourself');
    }
    await _contactRepository.upsert(
      viewerId: viewerId,
      subjectId: subjectId,
      contactName: normalizeName(contactName),
    );
  }

  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) => _contactRepository.delete(
    viewerId: viewerId,
    subjectId: subjectId,
  );

  Future<List<UserContactEntity>> fetchMine({
    required String viewerId,
  }) => _contactRepository.fetchAllByViewer(viewerId: viewerId);
}
