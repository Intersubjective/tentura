import '../database/tentura_db.dart';
import 'constellation_field_repository.dart' show readCustomSelectTimestamptz;

/// The undo window as the database holds it — read back rather than computed,
/// so the answer is the same clock undo will enforce against.
///
/// Shared by the clear and the sweep, which both answer with the window of
/// the `attention_clear_operation` row they wrote.
Future<DateTime?> readAttentionClearUndoDeadline(
  TenturaDb database,
  String operationId,
) async {
  final row = await database
      .customSelect(
        r'''
SELECT undo_deadline FROM public.attention_clear_operation WHERE id = $1
''',
        variables: [Variable<String>(operationId)],
      )
      .getSingleOrNull();
  // Drift reads a customSelect `timestamptz` as unix seconds and
  // `int.parse`s the driver's `DateTime.toString()`; this helper is the
  // repo's existing way round that.
  return readCustomSelectTimestamptz(row?.data['undo_deadline']);
}
