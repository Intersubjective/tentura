import 'package:tentura_root/domain/entity/localizable.dart';

/// #479: the plan step offered after a «Who'll take it?» pick was saved.
final class BatonPlanStepCreatedMessage extends LocalizableMessage {
  const BatonPlanStepCreatedMessage();

  @override
  String get toEn => 'Step added to the plan.';

  @override
  String get toRu => 'Шаг добавлен в план.';
}

/// #479: the person who took it left the discussion before the step was
/// saved, so it could not be given to them.
final class BatonPlanStepAssigneeLeftMessage extends LocalizableMessage {
  const BatonPlanStepAssigneeLeftMessage({required this.name});

  final String name;

  @override
  String get toEn =>
      '$name is no longer in the discussion, so the step was not added.';

  @override
  String get toRu =>
      '$name больше не участвует в обсуждении, поэтому шаг не добавлен.';
}
