part of '_migrations.dart';

/// Drop legacy coordination-item body text (title-only model).
final m0150 = Migration('0150', [
  "UPDATE public.coordination_item SET body = '';",
]);
