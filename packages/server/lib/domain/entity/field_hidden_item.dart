import 'package:tentura_server/domain/exception.dart';

/// Stored independently of beacon kind so later Field target kinds can extend
/// this protocol without changing the key or introducing another hide store.
enum FieldTargetKind {
  request(0),
  post(1);

  const FieldTargetKind(this.value);
  final int value;

  static FieldTargetKind parse(int value) => switch (value) {
    0 => request,
    1 => post,
    _ => throw IdWrongException(id: 'Field target kind $value'),
  };
}

typedef FieldHiddenItem = ({
  FieldTargetKind targetKind,
  String targetId,
  String title,
  String authorId,
  DateTime hiddenAt,
});
