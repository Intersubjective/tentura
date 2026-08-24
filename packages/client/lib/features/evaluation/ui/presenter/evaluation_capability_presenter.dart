import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

String presentAcknowledgedCapabilities(Iterable<String> slugs, L10n l10n) {
  final selected = slugs.toSet();
  final names = CapabilityTag.values
      .where((tag) => selected.contains(tag.slug))
      .map((tag) => tag.labelOf(l10n))
      .toList();
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} ${l10n.evaluationCapabilityAdditional(names.length - 2)}';
}
