// A person whose offer the Request's author declined is not someone who
// withdrew their commitment. The involvement query carries them as
// `declinedOfferIds`; the Forward picker must give them their own state
// (checked before "withdrawn", since the server may list the same person in
// both) and its own copy in every locale.
//
// These tests go through the real `ForwardRepository` and Ferry link chain
// (only HTTP faked); the pure `ForwardCase.computeInvolvement` rules are in
// `forward_compute_involvement_declined_offer_test.dart`.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';
import 'support/forward_wire_involvement.dart';

const _declined = 'Udeclined0001';
const _withdrawer = 'Uwithdrew0001';

void main() {
  group('author-declined offer on the involvement wire', () {
    test('an id in declinedOfferIds maps to offerDeclinedByAuthor', () async {
      final inv = await fetchWireInvolvement(declinedOfferIds: [_declined]);

      expect(
        ForwardCase.computeInvolvement(_declined, inv),
        CandidateInvolvement.offerDeclinedByAuthor,
      );
    });

    test('declined wins when the same id is also in withdrawnIds', () async {
      final inv = await fetchWireInvolvement(
        declinedOfferIds: [_declined],
        withdrawnIds: [_declined],
      );

      expect(
        ForwardCase.computeInvolvement(_declined, inv),
        CandidateInvolvement.offerDeclinedByAuthor,
      );
    });

    test('an id only in withdrawnIds still maps to withdrawn', () async {
      final inv = await fetchWireInvolvement(
        declinedOfferIds: [_declined],
        withdrawnIds: [_withdrawer],
      );

      expect(
        ForwardCase.computeInvolvement(_withdrawer, inv),
        CandidateInvolvement.withdrawn,
      );
      expect(
        ForwardCase.computeInvolvement(_declined, inv),
        CandidateInvolvement.offerDeclinedByAuthor,
        reason: 'the withdrawer must not drag the declined person with it',
      );
    });

    test('a person in neither list is not marked declined', () async {
      final inv = await fetchWireInvolvement(
        declinedOfferIds: [_declined],
        withdrawnIds: [_withdrawer],
      );

      expect(
        ForwardCase.computeInvolvement('Ubystander0001', inv),
        isNot(CandidateInvolvement.offerDeclinedByAuthor),
      );
    });

    test('the client asks the server for declinedOfferIds', () async {
      final sent = <WireSent>[];
      await fetchWireInvolvement(sent: sent);

      final query = sent.singleWhere(
        (s) => s.operationName == 'BeaconInvolvementData',
      );
      expect(query.variables['id'], isNotEmpty);
      expect(beaconInvolvementQueryText(), contains('declinedOfferIds'));
    });
  });

  group('offer-declined row copy', () {
    late ForwardCandidate candidate;

    setUp(() async {
      final inv = await fetchWireInvolvement(declinedOfferIds: [_declined]);
      candidate = ForwardCandidate(
        profile: const Profile(
          id: _declined,
          displayName: 'Carol',
          rScore: 1,
          score: 40,
        ),
        involvement: ForwardCase.computeInvolvement(_declined, inv),
      );
    });

    String label(Locale locale) =>
        forwardRecipientRelationLabel(lookupL10n(locale), candidate);

    test('English says "Offer declined"', () {
      expect(label(const Locale('en')), 'Offer declined');
    });

    test('every ARB locale is supported by the generated L10n', () {
      // Run from packages/client: the ARB files are listed by relative path.
      final arbLocales = {
        for (final f in Directory('l10n').listSync().whereType<File>())
          if (RegExp(r'app_(\w+)\.arb$').firstMatch(f.path) case final m?)
            m.group(1),
      };
      expect(
        L10n.supportedLocales.map((l) => l.languageCode).toSet(),
        containsAll(arbLocales),
      );
    });

    test('every locale has its own copy, not the withdrawal one', () {
      for (final locale in L10n.supportedLocales) {
        final l10n = lookupL10n(locale);
        final text = label(locale);
        expect(text.trim(), isNotEmpty, reason: '$locale');
        expect(text, isNot(l10n.forwardWithdrawn), reason: '$locale');
        if (locale.languageCode != 'en') {
          expect(
            text,
            isNot('Offer declined'),
            reason: '$locale falls back to the English text',
          );
        }
      }
    });
  });
}
