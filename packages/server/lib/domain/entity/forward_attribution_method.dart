enum ForwardAttributionMethod {
  explicitSingle('explicit_single'),
  explicitMultiple('explicit_multiple'),
  openedVia('opened_via');

  const ForwardAttributionMethod(this.key);

  final String key;
}
