import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tentura/features/contacts/data/service/contact_file_parser.dart';
import 'package:test/test.dart';

const _fixtureDirectory = 'test/features/contacts/fixtures';

Uint8List _fixtureBytes(String fixture) =>
    File('$_fixtureDirectory/$fixture').readAsBytesSync();

Uint8List _vCardFixtureBytes(String fixture, {required String lineEnding}) {
  final text = utf8.decode(_fixtureBytes(fixture));
  // Exercise the specified line ending even if checkout normalized the file.
  return utf8.encode(text.replaceAll(RegExp(r'\r?\n'), lineEnding));
}

void _expectContact(
  ImportedContact contact, {
  required String name,
  List<String> emails = const [],
  List<String> phones = const [],
  List<int>? photoBytes,
}) {
  expect(contact.name, name);
  expect(contact.emails, orderedEquals(emails));
  expect(contact.phones, orderedEquals(phones));
  expect(
    contact.photoBytes,
    photoBytes == null ? isNull : orderedEquals(photoBytes),
  );
}

void main() {
  group('vCard contact parsing', () {
    test(
      'vCard 3 unfolds CRLF space continuations in names and photos',
      () {
        final photo = _fixtureBytes('contact_photo.jpg');
        final contacts = parseVCard(
          _vCardFixtureBytes('vcard_3.vcf', lineEnding: '\r\n'),
        );

        expect(contacts, hasLength(1));
        _expectContact(
          contacts.single,
          name: 'Anna Petrova',
          emails: ['Anna.Petrova@example.test', 'anna.work@example.test'],
          phones: ['+1 (555) 123-4567', '+15557654321'],
          photoBytes: photo,
        );
      },
    );

    test(
      'vCard 4 unfolds LF tab continuations, strips tel: and decodes photos',
      () {
        final photo = _fixtureBytes('contact_photo.jpg');
        final contacts = parseVCard(
          _vCardFixtureBytes('vcard_4.vcf', lineEnding: '\n'),
        );

        expect(contacts, hasLength(1));
        _expectContact(
          contacts.single,
          name: 'Elena Ivanova',
          emails: ['elena.ivanova@example.test', 'elena.office@example.test'],
          phones: ['+15551234567'],
          photoBytes: photo,
        );
      },
    );

    test(
      'keeps cards in order and accepts grouped and mixed-case fields',
      () {
        final contacts = parseVCard(_fixtureBytes('vcard_address_book.vcf'));

        expect(contacts, hasLength(3));
        _expectContact(
          contacts[0],
          name: 'Anna Petrova',
          emails: ['Anna.Home@example.test', 'Anna.Other@example.test'],
          phones: ['+15551112222'],
        );
        _expectContact(
          contacts[1],
          name: r'Rosa, Jr.; R\D',
          phones: ['+15553334444'],
        );
        _expectContact(
          contacts[2],
          name: '',
          emails: ['nameless@example.test'],
        );
      },
    );

    test(
      'skips incomplete cards and keeps contacts with invalid photos',
      () {
        final contacts = parseVCard(_fixtureBytes('vcard_malformed.vcf'));

        expect(
          contacts.map((contact) => contact.name),
          orderedEquals(['Before', 'After', 'Complete']),
          reason: 'Only complete cards with usable contact details survive.',
        );
        _expectContact(
          contacts[0],
          name: 'Before',
          emails: ['before@example.test'],
        );
        _expectContact(contacts[1], name: 'After', phones: ['+15551234567']);
        _expectContact(contacts[2], name: 'Complete');
      },
    );
  });

  group('Google Contacts CSV parsing', () {
    test(
      'reads BOM-prefixed exports and splits ordered contact details',
      () {
        final contacts = parseGoogleContactsCsv(
          _fixtureBytes('google_contacts.csv'),
        );

        expect(contacts, hasLength(4));
        _expectContact(
          contacts[0],
          name: 'Anna Petrova',
          emails: [
            'Anna.Home@example.test',
            'anna.other@example.test',
            'anna.work@example.test',
          ],
          phones: ['+1 (555) 123-4567', '+15557654321'],
        );
        _expectContact(
          contacts[1],
          name: 'Elena Ivanova',
          emails: ['elena.work@example.test'],
        );
        _expectContact(
          contacts[2],
          name: 'Ben Jones',
          phones: ['+15551112222'],
        );
        _expectContact(
          contacts[3],
          name: '',
          emails: ['nameless@example.test'],
        );
      },
    );

    test(
      'preserves commas, doubled quotes and line breaks inside fields',
      () {
        final contacts = parseGoogleContactsCsv(
          _fixtureBytes('google_contacts_quoted.csv'),
        );

        expect(contacts, hasLength(2));
        _expectContact(
          contacts[0],
          name: 'Ada, "AJ" Jones',
          emails: ['ada@example.test'],
          phones: ['+15551112222'],
        );
        _expectContact(
          contacts[1],
          name: 'Rose\nMarie Curie',
          emails: ['rose@example.test'],
          phones: ['+15552223333'],
        );
      },
    );

    test(
      'prefers the legacy display name and falls back to given and family',
      () {
        final contacts = parseGoogleContactsCsv(
          _fixtureBytes('google_contacts_legacy.csv'),
        );

        expect(contacts, hasLength(2));
        _expectContact(
          contacts[0],
          name: 'Display Name',
          emails: ['display@example.test'],
        );
        _expectContact(
          contacts[1],
          name: 'Anna Petrova',
          phones: ['+15551112222'],
        );
      },
    );

    test(
      'skips unclosed quotes and unusable rows and preserves valid rows',
      () {
        final contacts = parseGoogleContactsCsv(
          _fixtureBytes('google_contacts_malformed.csv'),
        );

        expect(contacts, hasLength(2));
        _expectContact(
          contacts[0],
          name: 'Before',
          emails: ['before@example.test'],
        );
        _expectContact(contacts[1], name: 'After', phones: ['+15555550123']);
      },
    );

    test('returns no contacts from an empty file', () {
      expect(
        parseGoogleContactsCsv(_fixtureBytes('empty_contacts.csv')),
        isEmpty,
      );
      expect(
        parseGoogleContactsCsv(_fixtureBytes('google_contacts_legacy.csv')),
        hasLength(2),
      );
    });

    test(
      'returns no contacts when the header has no recognized columns',
      () {
        expect(
          parseGoogleContactsCsv(
            _fixtureBytes('google_contacts_unrecognized_header.csv'),
          ),
          isEmpty,
        );
        expect(
          parseGoogleContactsCsv(_fixtureBytes('google_contacts_legacy.csv')),
          hasLength(2),
        );
      },
    );
  });
}
