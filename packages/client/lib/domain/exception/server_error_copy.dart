/// Plain words for server error codes whose message is not fit to show (#683).
///
/// For these codes the server's `message` is an internal key
/// (`beaconNotOpen`) or technical English ("Room or item thread access
/// required"), so an error bar would show it raw. [RemoteApiException] reads
/// this table instead; the raw message stays for logs and "Copy details".
///
/// Codes are the server's `ExceptionCodes.codeNumber` (code space + enum
/// index), sent as `extensions.code`:
///  - 1000 general (`GeneralExceptionCode`),
///  - 1100 auth (`AuthExceptionCode`),
///  - 1500 help offer / coordination (`HelpOfferCoordinationExceptionCode`).
/// Codes with typed client exceptions of their own (closure, baton, plan,
/// hierarchy, constellation, Questions access) are mapped before this.
library;

typedef ServerErrorCopy = ({String en, String ru});

/// The plain copy for [code], or null when the server's own message is the
/// best there is.
ServerErrorCopy? serverErrorCopyFor(String? code) =>
    code == null ? null : kServerErrorCopy[code.trim()];

/// Server code (as sent) → copy. Every 1500-space code is listed; the guard
/// test keeps it in step with the server enum.
const kServerErrorCopy = <String, ServerErrorCopy>{
  // GeneralExceptionCode
  '1001': (
    en: 'Something in this request was not valid. Reload and try again.',
    ru: 'Что-то в этом запросе не так. Обновите страницу и повторите.',
  ),
  '1002': (
    en: 'This is no longer available. It may have been deleted.',
    ru: 'Это больше недоступно. Возможно, его удалили.',
  ),
  '1003': (
    en: 'This already exists.',
    ru: 'Это уже существует.',
  ),
  '1004': (
    en: 'This is too large to upload.',
    ru: 'Это слишком большое для загрузки.',
  ),
  '1005': (
    en: 'Too many attempts. Wait a moment and try again.',
    ru: 'Слишком много попыток. Подождите немного и повторите.',
  ),
  // AuthExceptionCode.authUnauthorizedException
  '1102': (
    en: "You don't have access to this.",
    ru: 'У вас нет доступа к этому.',
  ),
  // HelpOfferCoordinationExceptionCode
  '1500': (
    en:
        'This request is in its final check or closed, so it no longer '
        'takes offers or changes.',
    ru:
        'Запрос на подведении итогов или закрыт, поэтому больше не '
        'принимает предложения и изменения.',
  ),
  '1501': (
    en: 'Only the author of this request can do that.',
    ru: 'Это может сделать только автор запроса.',
  ),
  '1502': (
    en: "That kind of help can't be chosen here. Choose another.",
    ru: 'Такой вид помощи здесь выбрать нельзя. Выберите другой.',
  ),
  '1503': (
    en: 'Choose why you are withdrawing.',
    ru: 'Выберите, почему вы отзываете предложение.',
  ),
  '1504': (
    en: "That answer isn't available. Reload and try again.",
    ru: 'Такой ответ недоступен. Обновите страницу и повторите.',
  ),
  '1505': (
    en: "The request's status has changed. Reload and try again.",
    ru: 'Статус запроса изменился. Обновите страницу и повторите.',
  ),
  '1506': (
    en: 'This help offer is no longer active.',
    ru: 'Это предложение помощи уже не действует.',
  ),
  '1507': (
    en: "You can't offer help on your own request.",
    ru: 'Нельзя предложить помощь в собственном запросе.',
  ),
  '1508': (
    en:
        "You can't withdraw any more: the request is in its final check or "
        'closed.',
    ru: 'Отозвать предложение уже нельзя: запрос на подведении итогов или закрыт.',
  ),
  '1509': (
    en: 'Please give a reason.',
    ru: 'Укажите причину.',
  ),
  '1510': (
    en: 'The reason is too long. Shorten it and try again.',
    ru: 'Причина слишком длинная. Сократите её и повторите.',
  ),
  '1511': (
    en: 'This person is not in the discussion.',
    ru: 'Этого человека нет в обсуждении.',
  ),
  '1512': (
    en: 'This person is already in the discussion.',
    ru: 'Этот человек уже в обсуждении.',
  ),
  '1513': (
    en: "This help offer was already accepted, so it can't be declined now.",
    ru: 'Это предложение помощи уже принято, поэтому отклонить его нельзя.',
  ),
  '1514': (
    en: 'Accept the help offer before adding the person to the discussion.',
    ru: 'Сначала примите предложение помощи, затем добавьте человека в обсуждение.',
  ),
  '1515': (
    en: "This person's help offer was never accepted, so there is nothing to end.",
    ru: 'Предложение помощи этого человека не принималось, завершать нечего.',
  ),
  '1516': (
    en:
        'The request changed while you were writing. Check it and send your '
        'offer again.',
    ru:
        'Запрос изменился, пока вы писали. Проверьте его и отправьте '
        'предложение ещё раз.',
  ),
  '1517': (
    en: "That role name can't be used. Make it one short line.",
    ru: 'Такое название роли не подходит. Сделайте его короче, в одну строку.',
  ),
};
