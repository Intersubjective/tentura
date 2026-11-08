/// Server `beacon_help_offer.status` code.
enum HelpOfferStatus {
  /// The offer counts (status 0).
  active(0),

  /// The offer no longer counts (status 1): the helper withdrew it, or an
  /// author removal deactivated it (still re-admittable, #401).
  inactive(1);

  const HelpOfferStatus(this.smallintValue);

  final int smallintValue;

  static HelpOfferStatus? tryFromInt(int? value) {
    if (value == null) return null;
    return switch (value) {
      0 => active,
      1 => inactive,
      _ => null,
    };
  }
}
