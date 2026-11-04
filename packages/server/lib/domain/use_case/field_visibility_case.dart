import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/entity/field_search_result.dart';
import 'package:tentura_server/domain/entity/person_field_items_page.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/field_visibility_repository_port.dart';

@injectable
final class FieldVisibilityCase {
  const FieldVisibilityCase(this._repository);

  final FieldVisibilityRepositoryPort _repository;

  Future<FieldSearchResult> search({
    required String viewerId,
    required String query,
    required String context,
  }) {
    final folded = _fold(query);
    if (viewerId.trim().isEmpty || folded.runes.length < 2) {
      return Future.value(emptyFieldSearchResult);
    }
    return _repository.search(
      viewerId: viewerId,
      context: context,
      words: _words(folded),
    );
  }

  Future<PersonFieldItemsPage> personItems({
    required String viewerId,
    required String personId,
    required PersonFieldBucket bucket,
    String query = '',
    PersonFieldCursor? cursor,
  }) {
    if (personId.trim().isEmpty) throw IdWrongException(id: personId);
    return _repository.personItems(
      viewerId: viewerId,
      personId: personId,
      bucket: bucket,
      words: _words(_fold(query)),
      cursor: cursor,
    );
  }

  Future<void> setHidden({
    required String viewerId,
    required FieldTargetKind targetKind,
    required String targetId,
    required bool hidden,
  }) {
    if (targetId.trim().isEmpty) throw IdWrongException(id: targetId);
    return _repository.setHidden(
      viewerId: viewerId,
      targetKind: targetKind,
      targetId: targetId,
      hidden: hidden,
    );
  }

  Future<List<FieldHiddenItem>> hiddenItems({
    required String viewerId,
    DateTime? before,
  }) => _repository.hiddenItems(viewerId: viewerId, before: before);
}

String _fold(String query) =>
    query.toLowerCase().replaceAll('ё', 'е').replaceAll('@', '').trim();

// Match every word, including words separated by Unicode whitespace.
List<String> _words(String folded) => folded
    .split('')
    .map((character) => character.trim().isEmpty ? ' ' : character)
    .join()
    .split(' ')
    .where((word) => word.isNotEmpty)
    .toList();
