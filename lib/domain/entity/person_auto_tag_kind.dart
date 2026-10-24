/// Automatic people tags derived from facts (#699). The smallint is the
/// stable wire value shared by the server and the client.
enum PersonAutoTagKind {
  mutualContact(0, defaultShowInFilters: true),
  iTrust(1, defaultShowInFilters: true),
  trustsMe(2, defaultShowInFilters: false),
  helpedMe(3, defaultShowInFilters: true),
  iHelped(4, defaultShowInFilters: true),
  workedTogether(5, defaultShowInFilters: true),
  invited(6, defaultShowInFilters: false),
  forwarded(7, defaultShowInFilters: false),
  newOnField(8, defaultShowInFilters: true);

  const PersonAutoTagKind(
    this.smallintValue, {
    required this.defaultShowInFilters,
  });

  final int smallintValue;

  /// Whether the kind gets a Field filter row until the owner says otherwise.
  final bool defaultShowInFilters;

  static PersonAutoTagKind fromSmallint(int value) =>
      values.firstWhere(
        (k) => k.smallintValue == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'unknown automatic tag kind',
        ),
      );
}
