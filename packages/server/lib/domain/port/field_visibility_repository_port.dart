import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/entity/field_search_result.dart';
import 'package:tentura_server/domain/entity/person_field_items_page.dart';

abstract class FieldVisibilityRepositoryPort {
  /// Search Field-eligible, readable content, including personal hides and
  /// ended content. [words] are already normalized by the use case.
  Future<FieldSearchResult> search({
    required String viewerId,
    required String context,
    required List<String> words,
  });

  /// Readable published items for one author; counts precede cursor paging.
  Future<PersonFieldItemsPage> personItems({
    required String viewerId,
    required String personId,
    required PersonFieldBucket bucket,
    required List<String> words,
    PersonFieldCursor? cursor,
  });

  /// Checks target readability and changes only [viewerId]'s row atomically.
  Future<void> setHidden({
    required String viewerId,
    required FieldTargetKind targetKind,
    required String targetId,
    required bool hidden,
  });

  Future<List<FieldHiddenItem>> hiddenItems({
    required String viewerId,
    DateTime? before,
  });
}
