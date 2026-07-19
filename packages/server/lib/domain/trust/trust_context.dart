/// Writable trust source contexts (legacy is migration-only; effective is
/// `user_trust_edge`).
enum TrustContext {
  personal('personal'),
  commitment('commitment'),
  forward('forward');

  const TrustContext(this.key);

  final String key;
}
