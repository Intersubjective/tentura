/// How the user classified an offer-help submission (analytics / breadcrumbs).
enum OfferHelpClassificationPath {
  /// Submitted with free text and no capability chips.
  textOnly,

  /// Selected chips only from the suggested row (never opened full browse).
  suggestedChip,

  /// Opened the full category browser (or selected a chip only available there).
  fullBrowser,
}

/// Derives [OfferHelpClassificationPath] from selection + browse interaction.
OfferHelpClassificationPath resolveOfferHelpClassificationPath({
  required Set<String> selectedSlugs,
  required Set<String> suggestedSlugsAtSubmit,
  required bool browsedFullTaxonomy,
}) {
  if (selectedSlugs.isEmpty) {
    return OfferHelpClassificationPath.textOnly;
  }
  if (browsedFullTaxonomy) {
    return OfferHelpClassificationPath.fullBrowser;
  }
  if (selectedSlugs.every(suggestedSlugsAtSubmit.contains)) {
    return OfferHelpClassificationPath.suggestedChip;
  }
  return OfferHelpClassificationPath.fullBrowser;
}
