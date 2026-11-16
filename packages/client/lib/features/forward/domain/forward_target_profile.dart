/// Which forward affordances apply to the beacon being forwarded.
enum ForwardTargetProfile {
  request,
  post,

  /// Inviting Post members to a Request budded from that Post: the picker
  /// lists the Post's invitable members only.
  postBudInvite;

  bool get _isRequest => this == request;

  bool get _isPostBudInvite => this == postBudInvite;

  bool get showsBand => _isRequest;

  bool get showsReasons => _isRequest;

  bool get showsPersonalNotes => _isRequest || _isPostBudInvite;

  bool get showsLineage => _isRequest;

  bool get showsAttribution => _isRequest;

  bool get showsRequirements => _isRequest;

  bool get nudgesOfferHelp => _isRequest;

  bool get showsInviteNewPersonBar => !_isPostBudInvite;

  bool get showsTagChips => !_isPostBudInvite;

  /// «Not yet seen / Already involved» links.
  bool get showsScopeLinks => !_isPostBudInvite;

  /// Whether band and lineage people leave the main list for their own
  /// sections. The invite step has neither, so it lists every member.
  bool get setsAsideBandAndLineage => !_isPostBudInvite;

  /// The shared note and the picker's send composer.
  bool get showsSharedComposer => !_isPostBudInvite;
}
