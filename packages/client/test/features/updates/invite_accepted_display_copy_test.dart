import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('resolveInviteAcceptedDisplayCopy', () {
    test('loading keeps server title and body', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Alice · @alice',
        receiptBody:
            'Created an account via your invitation. You are now connected.',
        presentationPayloadJson: '{"inviteOrigin":"new_account"}',
        presentationKey: 'invite_accepted',
        l10n: l10n,
      );
      expect(copy.title, 'Alice · @alice');
      expect(
        copy.body,
        'Created an account via your invitation. You are now connected.',
      );
      expect(copy.secondary, isEmpty);
    });

    test('legacy empty payload with unknown body uses generic copy', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Carol joined via your invitation',
        receiptBody: 'Carol is now on Tentura.',
        presentationPayloadJson: '{}',
        presentationKey: 'invite_accepted',
        l10n: l10n,
        profile: const Profile(id: 'invitee-1', displayName: 'Carol'),
      );
      expect(copy.title, 'Carol');
      expect(copy.body, l10n.updatesFallbackBodyInviteAccepted);
      expect(copy.secondary, isEmpty);
    });

    test('nickname title with canonical secondary and new-account body', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Alice · @alice',
        receiptBody:
            'Created an account via your invitation. You are now connected.',
        presentationPayloadJson: '{"inviteOrigin":"new_account"}',
        presentationKey: 'invite_accepted',
        l10n: l10n,
        profile: const Profile(
          id: 'invitee-1',
          contactName: 'Mom',
          displayName: 'Alice',
          handle: 'alice',
        ),
      );
      expect(copy.title, 'Mom');
      expect(copy.secondary, 'Alice · @alice');
      expect(
        copy.body,
        'Created an account via your invitation. You are now connected.',
      );
    });

    test('omits secondary when it equals the composed title', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Alice · @alice',
        receiptBody: 'Already had a Tentura account. You are now connected.',
        presentationPayloadJson: '{"inviteOrigin":"existing_account"}',
        presentationKey: 'invite_accepted',
        l10n: l10n,
        profile: const Profile(
          id: 'invitee-1',
          displayName: 'Alice',
          handle: 'alice',
        ),
      );
      expect(copy.title, 'Alice');
      expect(copy.secondary, '@alice');
      expect(
        copy.body,
        'Already had a Tentura account. You are now connected.',
      );
    });
  });

  group('resolveInviteAcceptedDisplayCopy in Russian (#712)', () {
    final ru = lookupL10n(const Locale('ru'));
    const newAccountEn =
        'Created an account via your invitation. You are now connected.';
    const existingAccountEn =
        'Already had a Tentura account. You are now connected.';

    test('old row with no inviteOrigin payload is localized', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'tab qa 05',
        receiptBody: newAccountEn,
        presentationPayloadJson: '{}',
        presentationKey: 'invite_accepted',
        l10n: ru,
        profile: const Profile(id: 'invitee-1', displayName: 'tab qa 05'),
      );
      expect(copy.title, 'tab qa 05');
      expect(copy.body, ru.updatesInviteAcceptedBodyNewAccount);
      expect(copy.body, isNot(newAccountEn));
    });

    test('old row is localized while the profile is not loaded', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'tab qa 05',
        receiptBody: newAccountEn,
        presentationPayloadJson: '',
        presentationKey: 'invite_accepted',
        l10n: ru,
      );
      expect(copy.title, 'tab qa 05');
      expect(copy.body, ru.updatesInviteAcceptedBodyNewAccount);
    });

    test('payload origin is localized while the profile is not loaded', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'tab qa 05',
        receiptBody: newAccountEn,
        presentationPayloadJson: '{"inviteOrigin":"new_account"}',
        presentationKey: 'invite_accepted',
        l10n: ru,
      );
      expect(copy.body, ru.updatesInviteAcceptedBodyNewAccount);
    });

    test('old existing-account row is localized', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Nina',
        receiptBody: existingAccountEn,
        presentationPayloadJson: '{}',
        presentationKey: 'invite_accepted',
        l10n: ru,
      );
      expect(copy.body, ru.updatesInviteAcceptedBodyExistingAccount);
    });

    test('unknown stored body falls back to localized generic copy', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Invitation accepted',
        receiptBody: 'Carol is now on Tentura.',
        presentationPayloadJson: '{}',
        presentationKey: 'invite_accepted',
        l10n: ru,
      );
      expect(copy.title, ru.updatesFallbackTitleInviteAccepted);
      expect(copy.body, ru.updatesFallbackBodyInviteAccepted);
    });

    test('current row with payload and profile stays localized', () {
      final copy = resolveInviteAcceptedDisplayCopy(
        receiptTitle: 'Helper Two',
        receiptBody: newAccountEn,
        presentationPayloadJson: '{"inviteOrigin":"new_account"}',
        presentationKey: 'invite_accepted',
        l10n: ru,
        profile: const Profile(id: 'invitee-2', displayName: 'Helper Two'),
      );
      expect(copy.title, 'Helper Two');
      expect(copy.body, ru.updatesInviteAcceptedBodyNewAccount);
    });
  });
}
