import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura/features/phantoms/domain/entity/person_note.dart';
import 'package:tentura/features/phantoms/domain/port/person_note_repository_port.dart';

import '../entity/constellation_field_search_result.dart';
import '../port/constellation_field_search_port.dart';

@lazySingleton
final class ConstellationFieldSearchCase {
  ConstellationFieldSearchCase(this._port) : _notes = null;

  @factoryMethod
  ConstellationFieldSearchCase.withNotes(
    this._port,
    PersonNoteRepositoryPort notes,
  ) : _notes = notes;

  final ConstellationFieldSearchPort _port;
  final PersonNoteRepositoryPort? _notes;

  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) async {
    final results = _port.search(query: query, context: context);
    final notes = _notes;
    if (notes == null) return results;
    final (named, subjects) = await (results, _searchNotes(notes, query)).wait;
    return ConstellationFieldSearchResult(
      people: named.people,
      requests: named.requests,
      posts: named.posts,
      noteSubjects: subjects,
    );
  }

  Future<List<PersonNoteSubject>> _searchNotes(
    PersonNoteRepositoryPort notes,
    String query,
  ) async {
    try {
      return await notes.search(query);
    } on Exception {
      // A failed note lookup leaves name, Request and Post results available.
      return const [];
    }
  }
}
