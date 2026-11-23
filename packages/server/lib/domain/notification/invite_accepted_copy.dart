/// The fixed bodies of an invite-accepted notification, in English and
/// Russian.
///
/// The English body is what gets stored when the notification is written;
/// [russianForStoredBody] translates the stored body at delivery time.
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

  static const _englishRequest = 'The Request';
  static const _englishUnavailable =
      ' is no longer available through this invitation.';

  static String withLapsedRequest(
    String body,
    String? requestTitle, {
    bool ru = false,
  }) {
    if (requestTitle == null) return body;
    final title = requestTitle.trim();
    final label = title.isEmpty ? '' : ' «$title»';
    final outcome = ru
        ? 'Запрос$label больше недоступен по этому приглашению.'
        : '$_englishRequest$label$_englishUnavailable';
    return '$body $outcome';
  }

  /// Translates fixed copy and its optional lapsed Request sentence.
  static String? russianForStoredBody(String body) {
    final separator = body.indexOf(' $_englishRequest');
    if (separator == -1) return forStoredBody(body)?.ru;

    final copy = forStoredBody(body.substring(0, separator));
    if (copy == null) return null;

    final suffix = body.substring(separator + 1);
    if (suffix == '$_englishRequest$_englishUnavailable') {
      return withLapsedRequest(copy.ru, '', ru: true);
    }

    const prefix = '$_englishRequest «';
    const ending = '»$_englishUnavailable';
    if (!suffix.startsWith(prefix) || !suffix.endsWith(ending)) return null;

    final title = suffix.substring(
      prefix.length,
      suffix.length - ending.length,
    );
    return withLapsedRequest(copy.ru, title, ru: true);
  }

  /// The variant whose English body is exactly [body], or null.
  static InviteAcceptedCopy? forStoredBody(String body) {
    for (final copy in values) {
      if (copy.en == body) return copy;
    }
    return null;
  }
}
