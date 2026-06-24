import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';

void main() {
  const renderer = EmailTemplateRenderer();

  const notification = EmailNotificationContent(
    item: EmailNotificationItem(
      title: 'Asked of you',
      body: 'Review the wiring plan',
      url: 'https://t.example/#/beacon/view?id=b1&dest=room',
    ),
    unsubscribeUrl: 'https://t.example/email/unsubscribe?token=tok',
    managePrefsUrl: 'https://t.example/#/notifications',
  );

  group('renderNotification', () {
    test('subject is the item title; html + text carry body and link', () {
      final r = renderer.renderNotification(content: notification, locale: 'en');
      expect(r.subject, 'Asked of you');
      expect(r.text, contains('Review the wiring plan'));
      expect(r.text, contains(notification.item.url));
      expect(r.html, contains('Review the wiring plan'));
      expect(r.html, contains('Open in Tentura'));
      // Footer present in both parts.
      expect(r.text, contains('Unsubscribe'));
      expect(r.html, contains(notification.unsubscribeUrl));
    });

    test('renders Russian copy for ru locale', () {
      final r = renderer.renderNotification(content: notification, locale: 'ru');
      expect(r.html, contains('Открыть в Tentura'));
      expect(r.text, contains('Отписаться'));
    });

    test('escapes HTML in user content', () {
      const evil = EmailNotificationContent(
        item: EmailNotificationItem(
          title: '<script>x</script>',
          body: 'a & b < c',
          url: 'https://t.example/x',
        ),
        unsubscribeUrl: 'https://t.example/u',
        managePrefsUrl: 'https://t.example/m',
      );
      final r = renderer.renderNotification(content: evil, locale: 'en');
      expect(r.html, isNot(contains('<script>x</script>')));
      expect(r.html, contains('&lt;script&gt;'));
      expect(r.html, contains('a &amp; b &lt; c'));
    });
  });

  group('renderDigest', () {
    test('renders sections with items and skips empty sections', () {
      const digest = EmailDigestContent(
        sections: [
          EmailDigestSection(
            heading: 'Waiting on you',
            items: [
              EmailNotificationItem(
                title: 'Ask A',
                body: 'do the thing',
                url: 'https://t.example/a',
              ),
            ],
          ),
          EmailDigestSection(heading: 'Empty', items: []),
        ],
        unsubscribeUrl: 'https://t.example/u',
        managePrefsUrl: 'https://t.example/m',
      );
      final r = renderer.renderDigest(content: digest, locale: 'en');
      expect(r.subject, 'Your Tentura summary');
      expect(r.html, contains('Waiting on you'));
      expect(r.html, contains('Ask A'));
      expect(r.html, isNot(contains('Empty')));
      expect(r.text, contains('- Ask A'));
    });
  });
}
