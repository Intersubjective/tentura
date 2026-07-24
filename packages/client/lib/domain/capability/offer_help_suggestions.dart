import 'capability_tag.dart';

/// Max suggested chips shown on the offer-help sheet (before "Browse all").
const kOfferHelpMaxSuggestions = 6;

/// Light keyword → slug hints for offer-help suggestions (suggest only, never auto-select).
///
/// Matches English and Russian substrings against the offer message.
Iterable<String> keywordHintsFromOfferMessage(String message) sync* {
  final t = message.toLowerCase();
  if (t.isEmpty) return;

  bool has(Iterable<String> keys) => keys.any(t.contains);

  if (has(const [
    'sew',
    'sewing',
    'costume',
    'tailor',
    'craft',
    'handmade',
    'manual work',
    'шить',
    'шве',
    'костюм',
    'портн',
    'ручн',
    'рукодел',
  ])) {
    yield CapabilityTag.manualWork.slug;
  }
  if (has(const [
    'lift',
    'carry',
    'heavy',
    'muscle',
    'физич',
    'таскать',
    'поднять',
    'груз',
  ])) {
    yield CapabilityTag.physicalHelp.slug;
  }
  if (has(const ['repair', 'fix', 'handyman', 'ремонт', 'починить'])) {
    yield CapabilityTag.repair.slug;
  }
  if (has(const ['design', 'дизайн'])) {
    yield CapabilityTag.design.slug;
  }
  if (has(const ['translate', 'translation', 'перевод'])) {
    yield CapabilityTag.translation.slug;
  }
  if (has(const ['drive', 'transport', 'ride', 'транспорт', 'подвез'])) {
    yield CapabilityTag.transport.slug;
  }
  if (has(const ['tech', 'computer', 'laptop', 'техпомо', 'компьют'])) {
    yield CapabilityTag.techHelp.slug;
  }
}

/// Ordered suggestion slugs: author needs, keyword hints, then [CapabilityTag.other].
///
/// Only known [CapabilityTag] slugs are included. Caps at [maxSuggestions].
List<String> suggestOfferHelpSlugs({
  required String message,
  required Set<String> automaticSlugs,
  int maxSuggestions = kOfferHelpMaxSuggestions,
}) {
  final ordered = <String>[];

  void add(String slug) {
    if (ordered.contains(slug)) return;
    if (CapabilityTag.fromSlug(slug) == null) return;
    ordered.add(slug);
  }

  for (final slug in automaticSlugs) {
    add(slug);
  }
  for (final slug in keywordHintsFromOfferMessage(message)) {
    add(slug);
  }
  add(CapabilityTag.other.slug);

  if (ordered.length <= maxSuggestions) return ordered;
  return ordered.sublist(0, maxSuggestions);
}
