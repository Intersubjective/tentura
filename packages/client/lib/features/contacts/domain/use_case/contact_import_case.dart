import 'dart:typed_data';

import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/phantoms/domain/entity/person_note.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom_import.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';

typedef ContactImportEntry = ({PhantomImportContact contact, Uint8List? photo});

typedef RunContactImport =
    Future<List<PhantomImportOutcome>> Function(
      List<PhantomImportContact> rows,
      bool keepContacts,
      Future<List<PhantomImportOutcome>> Function(String operationId) import,
    );

final class ContactImportCase {
  ContactImportCase(
    this._people, {
    required this.runOperation,
    required this.preparePhoto,
    required this.uploadPhoto,
  });

  final PhantomRepositoryPort _people;
  final RunContactImport runOperation;
  final ImagePicked? Function(Uint8List) preparePhoto;
  final Future<void> Function(PhantomNoteSubject, ImagePicked) uploadPhoto;

  Future<List<PhantomImportOutcome>> run(
    List<ContactImportEntry> entries, {
    required bool keepContacts,
  }) {
    final rows = [for (final entry in entries) entry.contact];
    return runOperation(rows, keepContacts, (operationId) async {
      final outcomes = await _people.createBatch(
        rows: rows,
        keepContacts: keepContacts,
        clientOpId: operationId,
      );
      for (final created in outcomes.whereType<PhantomImportCreated>()) {
        final bytes = entries[created.rowIndex].photo;
        if (bytes == null) continue;
        final photo = preparePhoto(bytes);
        if (photo != null) {
          await uploadPhoto(PhantomNoteSubject(created.id), photo);
        }
      }
      return outcomes;
    });
  }
}
