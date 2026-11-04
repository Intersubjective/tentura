import 'field_hidden_item.dart';

/// Mutually exclusive tabs in a person's Field panel.
enum PersonFieldBucket { active, closed, hidden }

typedef PersonFieldCursor = ({DateTime activityAt, String id});

/// Display projection shared by Requests and Posts, not a content entity.
typedef PersonFieldItem = ({
  String id,
  FieldTargetKind kind,
  String authorId,
  String title,
  String rootExcerpt,
  int status,
  bool hidden,
  DateTime lastActivityAt,
  DateTime? expiresAt,
});

typedef PersonFieldItemsPage = ({
  List<PersonFieldItem> items,
  PersonFieldCursor? nextCursor,
  ({int active, int closed, int hidden}) counts,
});
