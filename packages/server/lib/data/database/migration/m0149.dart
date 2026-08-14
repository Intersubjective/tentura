part of '_migrations.dart';

/// Remove the retired coordination-resolution feature.
final m0149 = Migration('0149', [
  'DELETE FROM public.coordination_item WHERE kind = 4;',
]);
