import 'package:characters/characters.dart';

import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/notification/notification_text.dart';

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
    final rendered = item.subject != null;
    final heading = rendered
        ? '<a href="${_esc(item.url)}">${_esc(item.title)}</a>'
        : _esc(item.title);
    final excerpt = item.excerpt;
    final html = _wrap(
      body:
          '''
<h2>$heading</h2>
<p>${_esc(item.body)}</p>
${excerpt == null ? '' : '<blockquote>${_esc(excerpt)}</blockquote>\n'}<p><a href="${_esc(item.url)}">${_esc(t.openAction)}</a></p>
''',
      footer: _footerHtml(t, content.unsubscribeUrl, content.managePrefsUrl),
    );
    final text =
        '${item.title}\n\n${item.body}\n\n'
        '${excerpt == null ? '' : '"$excerpt"\n\n'}'
        '${t.openAction}: ${item.url}\n\n'
        '${_footerText(t, content.unsubscribeUrl, content.managePrefsUrl)}';
    return (subject: item.subject ?? item.title, html: html, text: text);
  }

  RenderedEmail renderDigest({
    required EmailDigestContent content,
    required String locale,
  }) {
    final t = _strings(locale);
    final htmlSections = StringBuffer();
    final textSections = StringBuffer();
    for (final section in content.sections) {
      if (section.entries.isEmpty) {
        continue;
      }
      htmlSections.write('<h3>${_esc(section.heading)}</h3><ul>');
      textSections.write('${section.heading}\n');
      for (final entry in section.entries) {
        final url = _esc(entry.url);
        switch (entry) {
          case EmailDigestGroup(:final label, :final lines):
            htmlSections.write('<li><a href="$url">${_esc(label)}</a><ul>');
            textSections.write('$label\n  ${entry.url}\n');
            for (final line in lines) {
              htmlSections.write('<li>${_esc(line)}</li>');
              textSections.write('- $line\n');
            }
            htmlSections.write('</ul></li>');
          case EmailDigestLine(:final text):
            htmlSections.write('<li><a href="$url">${_esc(text)}</a></li>');
            textSections.write('- $text\n  ${entry.url}\n');
        }
      }
      htmlSections.write('</ul>');
      textSections.write('\n');
    }
    final html = _wrap(
      body: '<p>${_esc(t.digestIntro)}</p>$htmlSections',
      footer: _footerHtml(t, content.unsubscribeUrl, content.managePrefsUrl),
    );
    final text =
        '${t.digestIntro}\n\n$textSections'
        '${_footerText(t, content.unsubscribeUrl, content.managePrefsUrl)}';
    return (subject: _digestSubject(content, t), html: html, text: text);
  }

  static const _subjectLimit = 78;

  /// `Tentura: «E1»` (+ `and {n} more`): the first group of the first
  /// non-empty section and how many other groups follow; generic when
  /// nothing is labelled or the recipient asked for redaction.
  String _digestSubject(EmailDigestContent content, _Strings t) {
    final labels = [
      for (final section in content.sections)
        for (final entry in section.entries)
          if (entry is EmailDigestGroup) entry.label,
    ];
    if (content.lockScreenSafe || labels.isEmpty) {
      return t.digestSubject;
    }
    final more = labels.length > 1 ? t.digestMore(labels.length - 1) : '';
    const prefix = 'Tentura: «';
    final room =
        _subjectLimit - prefix.length - '»'.length - more.characters.length;
    return '$prefix${NotificationText.truncate(labels.first, room)}»$more';
  }

  String _wrap({required String body, required String footer}) =>
      '''
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

  static String _enMore(int n) => ' and $n more';

  static String _ruMore(int n) => ' и ещё $n';

  static const _en = _Strings(
    openAction: 'Open in Tentura',
    digestSubject: 'Your Tentura summary',
    digestMore: _enMore,
    digestIntro:
        "Here's what's waiting on you and what moved while you were away.",
    manage: 'Manage notifications',
    unsubscribe: 'Unsubscribe',
  );

  static const _ru = _Strings(
    openAction: 'Открыть в Tentura',
    digestSubject: 'Сводка Tentura',
    digestMore: _ruMore,
    digestIntro: 'Вот что ждёт вас и что изменилось, пока вас не было.',
    manage: 'Настройки уведомлений',
    unsubscribe: 'Отписаться',
  );
}

class _Strings {
  const _Strings({
    required this.openAction,
    required this.digestSubject,
    required this.digestMore,
    required this.digestIntro,
    required this.manage,
    required this.unsubscribe,
  });

  final String openAction;
  final String digestSubject;
  final String Function(int n) digestMore;
  final String digestIntro;
  final String manage;
  final String unsubscribe;
}
