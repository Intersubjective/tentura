enum HelpOfferAdmissionAction {
  autoAdmit(0),
  accept(1),
  decline(2),
  remove(3);

  const HelpOfferAdmissionAction(this.smallintValue);

  final int smallintValue;

  static HelpOfferAdmissionAction? tryFromInt(int? value) {
    if (value == null) return null;
    return switch (value) {
      0 => autoAdmit,
      1 => accept,
      2 => decline,
      3 => remove,
      _ => null,
    };
  }
}
