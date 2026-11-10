/// The fixed bodies of an invite-accepted notification, in English and
/// Russian.
///
/// The English body is what gets stored when the notification is written;
/// [forStoredBody] finds the variant again when a stored notification is
/// delivered in another locale. One table for both sides keeps them in step.
enum InviteAcceptedCopy {
  newAccount(
    en: 'Created an account via your invitation. You are now connected.',
    ru: 'Создал(а) аккаунт по вашему приглашению. Теперь вы связаны.',
  ),
  existingAccount(
    en: 'Already had a Tentura account. You are now connected.',
    ru: 'Уже был аккаунт в Tentura. Теперь вы связаны.',
  ),
  connected(
    en: 'You are now connected on Tentura.',
    ru: 'Вы теперь связаны в Tentura.',
  );

  const InviteAcceptedCopy({required this.en, required this.ru});

  final String en;
  final String ru;

  /// The variant whose English body is exactly [body], or null.
  static InviteAcceptedCopy? forStoredBody(String body) {
    for (final copy in values) {
      if (copy.en == body) return copy;
    }
    return null;
  }
}
