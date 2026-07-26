part of '_input_types.dart';

/// `beaconSetMedia` argument set (§3.6): composes the existing
/// resolver-required [InputFieldImageIds], an optional cover id, and the
/// required `coverSource` integer. Never call `.nonNullable()` on the list
/// type itself (see `WORKAROUNDS.md`); [InputFieldImageIds.fromArgs] already
/// enforces argument presence.
abstract class InputFieldBeaconMedia {
  static final _coverImageId = InputFieldString(fieldName: 'coverImageId');

  static final _coverThumbImageId = InputFieldString(
    fieldName: 'coverThumbImageId',
  );

  static final _coverSource = InputFieldInt(fieldName: 'coverSource');

  static final imageIds = InputFieldImageIds.field;

  static final coverImageId = _coverImageId.fieldNullable;

  static final coverThumbImageId = _coverThumbImageId.fieldNullable;

  static final coverSource = _coverSource.fieldNonNullable;

  static List<String> imageIdsFromArgs(Map<String, dynamic> args) =>
      InputFieldImageIds.fromArgs(args);

  static String? coverImageIdFromArgs(Map<String, dynamic> args) =>
      _coverImageId.fromArgs(args);

  static bool coverThumbImageIdPresent(Map<String, dynamic> args) =>
      args.containsKey(_coverThumbImageId.field.name);

  static String? coverThumbImageIdFromArgs(Map<String, dynamic> args) =>
      _coverThumbImageId.fromArgs(args);

  static int coverSourceFromArgs(Map<String, dynamic> args) =>
      _coverSource.fromArgsNonNullable(args);
}
