import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _invitation = RegExp(
  'пригласил[аи]?|приглашени[еяюем]',
  caseSensitive: false,
);
final _closure = RegExp(
  '(?:^|[^а-яё])(?:закрыт[ао]?|закрылся|закрыли)(?![а-яё])',
  caseSensitive: false,
);
final _welcome = RegExp(
  'рады (?:вам|вас)|вам (?:всё ещё |по-прежнему )?рады|добро пожаловать',
  caseSensitive: false,
);
final russianConnectionCopy = RegExp(
  'на связи|связаны|установлена связь',
  caseSensitive: false,
);

Finder findRussianClosedRequestCopy({
  required String inviter,
  required String title,
  required bool welcomesNewAccount,
}) {
  final request = RegExp(
    '(?:^|[^а-яё])запрос(?:а|у|е|ом)?\\s+«${RegExp.escape(title)}»',
    caseSensitive: false,
  );
  return find.byWidgetPredicate(
    (widget) {
      if (widget is! RichText) return false;
      final text = widget.text.toPlainText();
      final prose = text
          .replaceAll(inviter, '')
          .replaceAll(title, '')
          .replaceAll('Tentura', '');
      return text.contains(inviter) &&
          !RegExp('[A-Za-z]').hasMatch(prose) &&
          request.hasMatch(text) &&
          _invitation.hasMatch(text) &&
          _closure.hasMatch(text) &&
          (!welcomesNewAccount ||
              _welcome.hasMatch(text) && russianConnectionCopy.hasMatch(text));
    },
    description: welcomesNewAccount
        ? 'Russian invitation, closed Request, welcome and connection copy'
        : 'Russian invitation and closed Request copy',
  );
}
