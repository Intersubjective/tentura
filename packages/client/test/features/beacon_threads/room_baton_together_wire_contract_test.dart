import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/exception/server_error_copy.dart';

void main() {
  late final String schema;

  setUpAll(() {
    schema = File('lib/data/gql/schema.graphql').readAsStringSync();
  });

  group('baton together GraphQL wire contract', () {
    test('respond mutation accepts partnerUserId', () {
      expect(
        schema,
        contains(
          'roomBatonRespond(batonId: String!, canHelp: Boolean!, '
          'partnerUserId: String): String',
        ),
      );
    });

    test('partnerRespond mutation is declared on mutation_root', () {
      expect(
        schema,
        contains(
          'roomBatonPartnerRespond(batonId: String!, inviterUserId: String!, '
          'accept: Boolean!): String',
        ),
      );
    });

    test('client operation documents include the new variables', () {
      final respond = File(
        'lib/features/beacon_threads/data/gql/room_baton_respond.graphql',
      ).readAsStringSync();
      expect(respond, contains(r'$partnerUserId: String'));
      expect(respond, contains(r'partnerUserId: $partnerUserId'));

      const partnerRespondPath =
          'lib/features/beacon_threads/data/gql/room_baton_partner_respond.graphql';
      expect(File(partnerRespondPath).existsSync(), isTrue);
      final partnerRespond = File(partnerRespondPath).readAsStringSync();
      expect(partnerRespond, contains(r'$inviterUserId: String!'));
      expect(partnerRespond, contains('roomBatonPartnerRespond'));
    });
  });

  group('together feature flag', () {
    test('is on in the released client', () {
      final consts = File('lib/consts.dart').readAsStringSync();
      expect(consts, contains('kBatonTogetherEnabled'));
      expect(consts, contains('kBatonTogetherEnabled = true'));
    });
  });

  group('partner error copy and codes', () {
    test('client mirrors baton partner exceptions', () {
      final exceptions = File(
        'lib/features/beacon_threads/domain/exception/baton_exceptions.dart',
      ).readAsStringSync();
      expect(exceptions, contains('BatonPartnerInvalidException'));
      expect(exceptions, contains('static const codeNumber = 1355'));
      expect(exceptions, contains('BatonNotPartnerException'));
      expect(exceptions, contains('static const codeNumber = 1356'));
      expect(exceptions, contains('case BatonPartnerInvalidException.codeNumber'));
      expect(exceptions, contains('case BatonNotPartnerException.codeNumber'));
    });

    test('plain EN and RU copy exists for partner errors', () {
      for (final code in ['1355', '1356']) {
        final copy = serverErrorCopyFor(code);
        expect(copy, isNotNull, reason: code);
        expect(copy!.en.trim(), isNotEmpty, reason: code);
        expect(copy.ru.trim(), isNotEmpty, reason: code);
        expect(RegExp('[а-яё]', caseSensitive: false).hasMatch(copy.ru), isTrue);
        expect(RegExp('[а-яё]', caseSensitive: false).hasMatch(copy.en), isFalse);
      }
    });
  });
}
