/// Outbound email for magic-link auth (implementation owns transport + markup).
abstract class EmailSenderPort {
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  });
}
