import '../../domain/exception/now_line_changed_exception.dart';

/// Throws [NowLineChangedException] for the next-step conflict GraphQL error
/// [code] (server 1348, #517), with the line and revision saved now; returns
/// normally for any other code, so the caller falls through to its generic
/// mapping.
void throwIfNowLineError(int? code, Map<String, dynamic>? extensions) {
  if (code != NowLineChangedException.codeNumber) return;
  final rawRevision = extensions?['currentRevision'];
  final rawBy = extensions?['updatedBy'];
  throw NowLineChangedException(
    currentLine: extensions?['currentLine']?.toString() ?? '',
    currentRevision: switch (rawRevision) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v) ?? 0,
      _ => 0,
    },
    updatedBy: rawBy is String ? rawBy : null,
  );
}
