class Place {
  const Place({
    this.country = '',
    this.locality = '',
  });

  final String country;

  final String locality;

  bool get isEmpty => country.isEmpty && locality.isEmpty;

  bool get isNotEmpty => country.isNotEmpty && locality.isNotEmpty;

  /// City / locality label for compact card metadata.
  String get displayLocality {
    final city = locality.trim();
    if (city.isNotEmpty) {
      return city;
    }
    final nation = country.trim();
    return nation.isEmpty ? toString() : nation;
  }

  @override
  String toString() => '$country${locality.isEmpty ? '' : ','} $locality';
}
