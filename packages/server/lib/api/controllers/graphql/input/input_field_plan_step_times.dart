part of '_input_types.dart';

/// `beaconFork(planStepTimes: [PlanStepTimeInput!])` (Request plan, #220
/// §4.10): the new time of each copied source step, by source step id.
/// Optional; entries without a `sourceStepId` are ignored.
abstract class InputFieldPlanStepTimes {
  static final field = GraphQLFieldInput(
    _fieldKey,
    _PlanStepTimeListType(),
    defaultsToNull: true,
  );

  static Map<String, ({DateTime? startAt, DateTime? endAt})> fromArgs(
    Map<String, dynamic> args,
  ) {
    final raw = args[_fieldKey];
    if (raw is! List) return const {};
    return {
      for (final entry in raw)
        if (entry is Map && entry['sourceStepId'] is String)
          entry['sourceStepId'] as String: (
            startAt: _instant(entry['startAt']),
            endAt: _instant(entry['endAt']),
          ),
    };
  }

  /// Like [InputFieldDatetime]: an offset-less value is read as UTC.
  static DateTime? _instant(Object? v) {
    final p = v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    if (p == null || p.isUtc) return p;
    return DateTime.utc(
      p.year,
      p.month,
      p.day,
      p.hour,
      p.minute,
      p.second,
      p.millisecond,
      p.microsecond,
    );
  }

  static const _fieldKey = 'planStepTimes';
}

/// `[PlanStepTimeInput!]` typed over `dynamic`, so a decoded `List<dynamic>`
/// of maps passes validation on executors that do not re-type variable lists.
final class _PlanStepTimeListType extends GraphQLListType<dynamic, dynamic> {
  _PlanStepTimeListType() : super(gqlInputPlanStepTime.nonNullable());

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}
