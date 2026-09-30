/// Ledger evidence kinds; [code] is `trust_kind_config.kind` (m0202).
enum TrustEvidenceKind {
  vouch(1),
  helped(2),
  marked(3),
  routed(4),
  usefulForward(5),
  engaged(6),
  noisy(7),
  workedWithAuthor(8),
  supportedColleague(9);

  const TrustEvidenceKind(this.code);

  final int code;
}
