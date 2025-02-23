import 'package:meta/meta.dart';

@immutable
class DateTimeRange {
  const DateTimeRange({this.start, this.end})
    : assert(
        start != null || end != null,
        'At least one parameter should be not null',
      );

  factory DateTimeRange.fromJson(Map<String, dynamic> json) => DateTimeRange(
    start: DateTime.tryParse(json['start'] as String? ?? ''),
    end: DateTime.tryParse(json['end'] as String? ?? ''),
  );

  final DateTime? start;

  final DateTime? end;

  @override
  bool operator ==(Object other) {
    if (other is DateTimeRange) {
      return other.start == start && other.end == end;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start - $end';

  Map<String, dynamic> toJson([DateTimeRange? i]) => {
    'start': (i?.start ?? start)?.toIso8601String(),
    'end': (i?.end ?? end)?.toIso8601String(),
  };
}
