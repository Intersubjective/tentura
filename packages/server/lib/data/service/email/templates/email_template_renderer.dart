import 'package:tentura_server/domain/entity/email_notification_content.dart';

/// Rendered email body in both MIME parts.
typedef RenderedEmail = ({String subject, String html, String text});

/// Pure EN/RU renderer for notification + digest emails. No I/O — the senders
/// own transport. Locale is a simple `'en'`/`'ru'` code (server has no Flutter
/// `Locale`); anything unknown falls back to English.
class EmailTemplateRenderer {
  const EmailTemplateRenderer();

  RenderedEmail renderNotification({
    required EmailNotificationContent content,
    required String locale,
  }) {
    final t = _strings(locale);
    final item = content.item;
    final html = _wrap(
      body: '''
<h2>${_esc(item.title)}</h2>
<p>${_esc(item.body)}</p>
<p><a href="${_esc(item.url)}">${_esc(t.openAction)}</a></p>
''',
      footer: _footerHtml(t, content.unsubscribeUrl, content.managePrefsUrl),
    );
    final text = '${item.title}\n\n${item.body}\n\n'
        '${t.openAction}: ${item.url}\n\n'
        '${_footerText(t, content.unsubscribeUrl, content.managePrefsUrl)}';
    return (subject: item.title, html: html, text: text);
  }

  RenderedEmail renderDigest({
    required EmailDigestContent content,
    required String locale,
  }) {
    final t = _strings(locale);
    final htmlSections = StringBuffer();
    final textSections = StringBuffer();
    for (final section in content.sections) {
      if (section.items.isEmpty) {
        continue;
      }
      htmlSections.write('<h3>${_esc(section.heading)}</h3><ul>');
      textSections.write('${section.heading}\n');
      for (final i in section.items) {
        htmlSections.write(
          '<li><a href="${_esc(i.url)}">${_esc(i.title)}</a>'
          '${i.body.isEmpty ? '' : ' — ${_esc(i.body)}'}</li>',
        );
        final suffix = i.body.isEmpty ? '' : ' — ${i.body}';
        textSections.write('- ${i.title}$suffix\n  ${i.url}\n');
      }
      htmlSections.write('</ul>');
      textSections.write('\n');
    }
    final html = _wrap(
      body: '<p>${_esc(t.digestIntro)}</p>$htmlSections',
      footer: _footerHtml(t, content.unsubscribeUrl, content.managePrefsUrl),
    );
    final text = '${t.digestIntro}\n\n$textSections'
        '${_footerText(t, content.unsubscribeUrl, content.managePrefsUrl)}';
    return (subject: t.digestSubject, html: html, text: text);
  }

  String _wrap({required String body, required String footer}) => '''
<div style="font-family: sans-serif; max-width: 560px; margin: 0 auto;">
$body
<hr/>
$footer
</div>
''';

  String _footerHtml(_Strings t, String unsubscribeUrl, String manageUrl) =>
      '<p style="color:#888; font-size:12px;">'
      '<a href="${_esc(manageUrl)}">${_esc(t.manage)}</a> · '
      '<a href="${_esc(unsubscribeUrl)}">${_esc(t.unsubscribe)}</a></p>';

  String _footerText(_Strings t, String unsubscribeUrl, String manageUrl) =>
      '${t.manage}: $manageUrl\n${t.unsubscribe}: $unsubscribeUrl';

  _Strings _strings(String locale) =>
      locale.toLowerCase().startsWith('ru') ? _ru : _en;

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static const _en = _Strings(
    openAction: 'Open in Tentura',
    digestSubject: 'Your Tentura summary',
    digestIntro: "Here's what's waiting on you and what moved while you were away.",
    manage: 'Manage notifications',
    unsubscribe: 'Unsubscribe',
  );

  static const _ru = _Strings(
    openAction: 'Открыть в Tentura',
    digestSubject: 'Сводка Tentura',
    digestIntro: 'Вот что ждёт вас и что изменилось, пока вас не было.',
    manage: 'Настройки уведомлений',
    unsubscribe: 'Отписаться',
  );
}

class _Strings {
  const _Strings({
    required this.openAction,
    required this.digestSubject,
    required this.digestIntro,
    required this.manage,
    required this.unsubscribe,
  });

  final String openAction;
  final String digestSubject;
  final String digestIntro;
  final String manage;
  final String unsubscribe;
}
