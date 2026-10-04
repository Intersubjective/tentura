/// Which forward affordances apply to the beacon being forwarded.
enum ForwardTargetProfile {
  request,
  post;

  bool get _isRequest => this == request;

  bool get showsBand => _isRequest;

  bool get showsReasons => _isRequest;

  bool get showsLineage => _isRequest;

  bool get showsAttribution => _isRequest;

  bool get showsRequirements => _isRequest;

  bool get nudgesOfferHelp => _isRequest;
}
