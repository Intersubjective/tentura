@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:intl/message_format.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/contacts/data/service/contact_file_parser.dart';
import 'package:tentura/features/contacts/domain/use_case/contact_import_case.dart';
import 'package:tentura/features/contacts/ui/bloc/contact_import_cubit.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom_import.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_composer_screen_harness.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../constellation/fixtures/constellation_reference_fixture.dart';
import '../phantoms/fixtures/private_avatar_wire.dart';

const _entry = 'Import from contacts';
const _import = 'Import';
const _usePhoto = 'Use their photo as my private picture';
const _keepDetails = 'Keep phone/email privately';
const _onMap = 'Already on my map';
const _shortName = 'Al';
const _createdId = 'PH123456789012';
const _secondId = 'PH123456789013';
const _noPhotoId = 'PH123456789014';
const _capRefusal = 'Remove someone not on Tentura yet first.';
const _batch = 'phantomCreateBatch';
const _upload = 'personPrivateAvatarUpload';
const _alreadyOnTentura = 'Already on Tentura — send them an invite yourself.';
const _checkLimit =
    "Couldn't check if they're already on Tentura: daily check limit reached.";
const _alreadyOnTenturaRu = 'Уже в Тентуре — отправьте приглашение сами.';
const _checkLimitRu =
    'Не удалось проверить, есть ли человек в Тентуре: дневной лимит проверок исчерпан.';
const _fixturePath = 'test/features/contacts/fixtures';
final _editingNeeded = RegExp(
  r'\b(edit(?: name)?|too short|at least (?:3|three)|minimum (?:3|three))\b',
  caseSensitive: false,
);
final _russianEditingNeeded = RegExp(
  'коротк|отредакт|исправ|изменить имя|не менее|как минимум|минимум|3 символ',
  caseSensitive: false,
);
final _internalName = RegExp('phantom|фантом', caseSensitive: false);
final _internalContactTerms = RegExp(
  'phantom|placeholder|фантом|заглушка',
  caseSensitive: false,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Contact match notices after import', () {
    test(
      'a batch requests and preserves each saved contact match answer',
      () async {
        final rows = [
          for (final (index, answer) in const [true, false, null].indexed)
            {
              '__typename': 'PhantomImportCreated',
              'rowIndex': index,
              'id': 'PH${index + 1}',
              'alreadyOnTentura': answer,
            },
        ];
        final contacts = parseVCard(
          _vCard(const [
            _Card('Anna Kim', email: 'anna@example.test'),
            _Card('Boris Lane', email: 'boris@example.test'),
            _Card('Nora James'),
          ]).bytes,
        );
        final sent = <WireSent>[];
        Set<String>? selectedFields;
        await withRemoteWire(
          {
            'PhantomCreateBatch': {
              '__typename': 'mutation_root',
              _batch: {
                '__typename': 'PhantomImportResult',
                'created': rows,
                'refused': <Object?>[],
              },
            },
          },
          sent,
          (remote) async {
            final cubit = ContactImportCubit(
              ContactImportCase(
                PhantomRepository(remote),
                runOperation: (_, _, submit) => submit('test-import'),
                preparePhoto: (_) => throw StateError('No contact has a photo'),
                uploadPhoto: (_, _) =>
                    throw StateError('No contact has a photo'),
              ),
              contacts,
            );
            try {
              for (final (index, _) in contacts.indexed) {
                cubit.select(index, selected: true);
              }
              expect(await cubit.submit(), isTrue);
              expect(sent.single.operationName, 'PhantomCreateBatch');
              expect(cubit.state.status, ContactImportStatus.ready);
              expect(cubit.state.rows.map((row) => row.created), [
                true,
                true,
                true,
              ]);
              final outcomes = cubit.state.rows
                  .map((row) => row.outcome)
                  .whereType<PhantomImportCreated>();
              expect(
                {
                  'requested match field': selectedFields?.contains(
                    'alreadyOnTentura',
                  ),
                  'saved contacts and answers in checklist order': [
                    for (final outcome in outcomes)
                      (outcome.id, _matchAnswer(outcome)),
                  ],
                },
                {
                  'requested match field': true,
                  'saved contacts and answers in checklist order': [
                    ('PH1', true),
                    ('PH2', false),
                    ('PH3', null),
                  ],
                },
              );
            } finally {
              await cubit.close();
            }
          },
          selectResponse: (query, data) {
            final operation = parseString(
              query,
            ).definitions.whereType<OperationDefinitionNode>().single;
            final created = _selectedField(
              _selectedField(operation.selectionSet, _batch).selectionSet!,
              'created',
            );
            final fields = created.selectionSet!.selections
                .whereType<FieldNode>()
                .map((field) => field.name.value)
                .toSet();
            selectedFields = fields;
            // GraphQL only returns the fields the operation actually selected.
            return {
              ...data,
              _batch: {
                ...data[_batch] as Map<String, Object?>,
                'created': [
                  for (final row in rows)
                    {
                      '__typename': row['__typename'],
                      for (final field in fields) field: row[field],
                    },
                ],
              },
            };
          },
        );
      },
    );

    testWidgets(
      'mixed answers stay with their saved rows and leave the sheet editable',
      (tester) async {
        const matched = 'Anna Kim';
        const limited = 'Boris Lane';
        const unmatched = 'Nora James';
        const next = 'Alex Park';
        await _withField(
          tester,
          _ContactPicker(
            _vCard(const [
              _Card(matched, email: 'anna@example.test'),
              _Card(limited, email: 'boris@example.test'),
              _Card(unmatched, email: 'nora@example.test'),
              _Card(next),
            ]),
          ),
          (flow) async {
            await flow.openChecklist();
            for (final name in [matched, limited, unmatched]) {
              await flow.tick(name);
            }
            final before = _displayedCopy();
            await flow.submit();
            expect(flow.rows.map((row) => row['email']), [
              'anna@example.test',
              'boris@example.test',
              'nora@example.test',
            ]);
            final l10n = lookupL10n(flow.locale);
            for (final name in [matched, limited, unmatched]) {
              _expectSavedRow(
                tester,
                name,
                l10n,
                others: const [matched, limited, unmatched, next],
              );
            }
            expect(find.text(l10n.contactImportRowRefused), findsNothing);
            expect(find.text(l10n.contactImportCapReached), findsNothing);
            expect(find.text(l10n.contactImportFailed), findsNothing);
            _expectPublicCopySince(before);
            final nextCheckbox = _contactCheck(next);
            expect(nextCheckbox, findsOneWidget);
            expect(tester.widget<Checkbox>(nextCheckbox).onChanged, isNotNull);

            final matches = find.text(_alreadyOnTentura);
            final limits = find.text(_checkLimit);
            expect(
              {
                'match notices': matches.evaluate().length,
                'limit notices': limits.evaluate().length,
                'match notice on $matched': _rowFor(
                  matched,
                  matches,
                  others: const [limited, unmatched, next],
                ).evaluate().length,
                'limit notice on $limited': _rowFor(
                  limited,
                  limits,
                  others: const [matched, unmatched, next],
                ).evaluate().length,
              },
              {
                'match notices': 1,
                'limit notices': 1,
                'match notice on $matched': 1,
                'limit notice on $limited': 1,
              },
            );
          },
          respond: (call) => call.field == _batch
              ? _batchResult(
                  call,
                  created: const {
                    unmatched: _noPhotoId,
                    limited: _secondId,
                    matched: _createdId,
                  },
                  matchAnswers: const {
                    matched: true,
                    limited: null,
                    unmatched: false,
                  },
                )
              : null,
        );
      },
    );

    testWidgets(
      'a saved row without email and a refused row show no match notices',
      (tester) async {
        const noEmail = 'Nora James';
        const refused = 'Boris Lane';
        const matched = 'Anna Kim';
        await _withField(
          tester,
          _ContactPicker(
            _vCard(const [
              _Card(noEmail),
              _Card(refused, email: 'boris@example.test'),
              _Card(matched, email: 'anna@example.test'),
            ]),
          ),
          (flow) async {
            await flow.openChecklist();
            for (final name in [noEmail, refused, matched]) {
              await flow.tick(name);
            }
            await flow.submit();
            final l10n = lookupL10n(flow.locale);
            expect(flow.rows.first['email'], isNull);
            _expectSavedRow(
              tester,
              noEmail,
              l10n,
              others: const [refused, matched],
            );
            expect(
              _rowFor(
                refused,
                find.text(l10n.contactImportCapReached),
                others: const [noEmail, matched],
              ),
              findsOneWidget,
            );
            expect(find.text(_checkLimit), findsNothing);
            final notice = find.text(_alreadyOnTentura);
            expect(notice, findsOneWidget);
            expect(
              _rowFor(matched, notice, others: const [noEmail, refused]),
              findsOneWidget,
            );
          },
          respond: (call) => call.field == _batch
              ? _batchResult(
                  call,
                  created: const {noEmail: _createdId, matched: _secondId},
                  refused: const {refused: _capRefusal},
                  matchAnswers: const {noEmail: null, matched: true},
                )
              : null,
        );
      },
    );

    for (final (answer, description, message, otherMessage) in const [
      (true, 'an existing account', _alreadyOnTenturaRu, _checkLimitRu),
      (null, 'the daily check limit', _checkLimitRu, _alreadyOnTenturaRu),
    ]) {
      testWidgets(
        'Russian phone checklist shows $description on the saved row',
        (tester) async {
          const name = 'Анна Ким';
          const other = 'Борис Лейн';
          const locale = Locale('ru');
          final l10n = lookupL10n(locale);
          await _withField(
            tester,
            _ContactPicker(
              _vCard(const [
                _Card(name, email: 'anna@example.test'),
                _Card(other),
              ]),
            ),
            (flow) async {
              await flow.openPicker(label: l10n.contactImportEntry);
              final options = [
                l10n.contactImportUsePhoto,
                l10n.contactImportKeepDetails,
              ];
              await _tap(tester, _contactCheck(name, options: options));
              final before = _displayedCopy();
              await flow.submit(label: l10n.contactImportAction);
              _expectSavedRow(tester, name, l10n, others: const [other]);
              expect(find.text(l10n.contactImportFailed), findsNothing);
              expect(find.text(otherMessage), findsNothing);
              _expectPublicCopySince(before);
              final notice = find.text(message);
              expect(notice, findsOneWidget);
              expect(
                _rowFor(name, notice, others: const [other]),
                findsOneWidget,
              );
            },
            respond: (call) => call.field == _batch
                ? _batchResult(
                    call,
                    created: const {name: _createdId},
                    matchAnswers: {name: answer},
                  )
                : null,
            locale: locale,
          );
        },
      );
    }
  });

  group('Importing people from a contact file', () {
    testWidgets(
      'the vCard opens one unchecked row per contact with no select-all',
      (
        tester,
      ) async {
        final file = _ContactFile.fixture('vcard_address_book.vcf');
        final parsed = parseVCard(file.bytes);
        expect(parsed, hasLength(3));

        await _withField(tester, _ContactPicker(file), (flow) async {
          await flow.openChecklist();

          expect(_rowChecks(), findsNWidgets(parsed.length));
          expect(
            _rowChecks().evaluate().map(
              (row) => (row.widget as Checkbox).value,
            ),
            everyElement(isFalse),
          );
          for (final contact in parsed.where(
            (contact) => contact.name.isNotEmpty,
          )) {
            expect(_contactCheck(contact.name), findsOneWidget);
          }
          final selectAll = RegExp(
            r'\b(select|check|tick)\s+all\b',
            caseSensitive: false,
          );
          expect(find.textContaining(selectAll), findsNothing);
          expect(find.bySemanticsLabel(selectAll), findsNothing);
          expect(_importButton().onPressed, isNull);
          expect(flow.batches, isEmpty);
        });
      },
    );

    for (final language in ['en', 'ru']) {
      testWidgets(
        'cancelling the $language file picker leaves the checklist closed',
        (
          tester,
        ) async {
          final copy = _ImportCopy(language);
          await _withField(tester, _ContactPicker(null), (flow) async {
            await flow.openAddPerson();
            final before = _displayedCopy();
            await flow.openPicker(
              label: copy.label(_entry),
              fromAddPerson: true,
            );

            expect(_rowChecks(), findsNothing);
            expect(_searchField(russian: language == 'ru'), findsNothing);
            expect(find.text(copy.label(_usePhoto)), findsNothing);
            expect(find.text(copy.label(_keepDetails)), findsNothing);
            expect(flow.batches, isEmpty);
            copy.expectLocalized(
              _displayedCopy().difference(before),
              stage: 'cancelled file picker',
              fixtureValues: const {},
            );
          }, locale: Locale(language));
        },
      );
    }

    testWidgets('CSV search ignores case and keeps selections on hidden rows', (
      tester,
    ) async {
      final csv = _ContactFile(
        'contacts.csv',
        utf8.encode('''
Name,E-mail 1 - Value
Joann Fox,joann@example.test
ANNE Stone,anne@example.test
Boris Lane,boris@example.test
'''),
      );
      await _withField(tester, _ContactPicker(csv), (flow) async {
        await flow.openChecklist();
        expect(_rowChecks(), findsNWidgets(3));
        await flow.tick('Boris Lane');
        expect(_selected(tester, 'Boris Lane'), isTrue);

        final search = _searchField();
        expect(search, findsOneWidget);
        await tester.enterText(search, 'aNn');
        await _settle(tester);
        expect(_rowChecks(), findsNWidgets(2));
        expect(_contactCheck('Joann Fox'), findsOneWidget);
        expect(_contactCheck('ANNE Stone'), findsOneWidget);
        expect(_contactCheck('Boris Lane'), findsNothing);

        await tester.enterText(search, '');
        await _settle(tester);
        expect(_rowChecks(), findsNWidgets(3));
        expect(_selected(tester, 'Boris Lane'), isTrue);
        expect(_selected(tester, 'Joann Fox'), isFalse);
        expect(_selected(tester, 'ANNE Stone'), isFalse);
        expect(flow.batches, isEmpty);
      });
    });

    for (final (name, partial, source) in const [
      ('mIRA Lane', 'Mira', 'a person without an account'),
      ('sAM Reed', 'Sam', 'a contact with an account'),
    ]) {
      testWidgets('an exact name match for $source is marked locally', (
        tester,
      ) async {
        final file = _names(['  $name  ', partial, 'Nora James']);
        await _withField(tester, _ContactPicker(file), (flow) async {
          await flow.openAddPerson();
          final callsBeforePicking = flow.wire.calls.length;
          await flow.openChecklist(fromAddPerson: true);

          final mark = _mark(_onMap);
          expect(_contactLabel(partial), findsOneWidget);
          expect(_contactLabel('Nora James'), findsOneWidget);
          expect(
            _rowFor(name, mark, others: [partial, 'Nora James']),
            findsOneWidget,
          );
          expect(mark, findsOneWidget);
          expect(
            flow.wire.calls.skip(callsBeforePicking),
            isEmpty,
            reason: 'Matching uses people already loaded on the Field',
          );
        });
      });
    }

    testWidgets(
      'a selected short name blocks import until the corrected name is submitted',
      (
        tester,
      ) async {
        await _withField(
          tester,
          _ContactPicker(_names([_shortName, 'Nora James'])),
          (
            flow,
          ) async {
            await flow.openChecklist();
            await flow.tick(_shortName);
            expect(_selected(tester, _shortName), isTrue);
            expect(
              _rowFor(_shortName, _editingMark(), others: const ['Nora James']),
              findsOneWidget,
            );
            expect(_importButton().onPressed, isNull);
            expect(flow.batches, isEmpty);

            await _editName(tester, _shortName, '  Alex  ');
            expect(_contactCheck('Alex'), findsOneWidget);
            expect(
              _rowFor('Alex', _editingMark(), others: const ['Nora James']),
              findsNothing,
            );
            expect(_importButton().onPressed, isNotNull);
            await flow.submit();
            expect(flow.rows.single['name'], 'Alex');
          },
        );
      },
    );

    testWidgets('import trims and limits a long name to 32 characters', (
      tester,
    ) async {
      const longName = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn';
      await _withField(tester, _ContactPicker(_names(['  $longName  '])), (
        flow,
      ) async {
        await flow.openChecklist();
        // The checklist may display the full name or its import-ready prefix.
        final row = _controlByLabel(
          find.textContaining(longName.substring(0, 32)),
          _rowChecks(),
        );
        await _tap(tester, row);
        await flow.submit();
        expect(flow.rows.single['name'], longName.substring(0, 32));
      });
    });

    for (final keep in [false, true]) {
      testWidgets(
        'contact details are sent for selected rows with private keeping ${keep ? 'on' : 'off'}',
        (
          tester,
        ) async {
          final file = _vCard(const [
            _Card(
              'Anna Home',
              email: 'anna@example.test',
              phone: '+15551111111',
            ),
            _Card(
              'Boris Work',
              email: 'boris@example.test',
              phone: '+15552222222',
            ),
            _Card(
              'Nora Home',
              email: 'nora@example.test',
              phone: '+15553333333',
            ),
          ]);
          await _withField(tester, _ContactPicker(file), (flow) async {
            await flow.openChecklist();
            expect(_toggleValue(tester, _keepDetails), isFalse);
            if (keep) {
              await _tap(tester, _toggle(_keepDetails));
              expect(_toggleValue(tester, _keepDetails), isTrue);
            }
            await flow.tick('Anna Home');
            await flow.tick('Nora Home');
            await flow.submit();

            expect(flow.batches.single.variables['keepContacts'], keep);
            expect(
              flow.rows,
              unorderedEquals([
                {
                  'name': 'Anna Home',
                  'email': 'anna@example.test',
                  'phone': '+15551111111',
                },
                {
                  'name': 'Nora Home',
                  'email': 'nora@example.test',
                  'phone': '+15553333333',
                },
              ]),
            );
            expect(flow.wire.uploads, isEmpty);
          });
        },
      );
    }

    testWidgets(
      'turning off the private photo option skips an available photo',
      (
        tester,
      ) async {
        final photo = _ContactFile.fixture('contact_photo.jpg').bytes;
        final file = _vCard([
          _Card('Nora James', photo: photo),
        ]);
        await _withField(tester, _ContactPicker(file), (flow) async {
          await flow.openChecklist();
          expect(_toggleValue(tester, _usePhoto), isTrue);
          await _tap(tester, _toggle(_usePhoto));
          expect(_toggleValue(tester, _usePhoto), isFalse);
          await flow.tick('Nora James');
          await flow.submit();

          expect(flow.rows.single['name'], 'Nora James');
          expect(flow.wire.uploads, isEmpty);
        });
      },
    );

    testWidgets(
      'only selected photos upload, one at a time, after the batch reply',
      (
        tester,
      ) async {
        final batchReply = Completer<void>();
        final firstUploadReply = Completer<void>();
        final firstPhoto = _jpeg(img.ColorRgb8(200, 10, 10));
        final secondPhoto = _jpeg(img.ColorRgb8(10, 10, 200));
        final file = _vCard([
          _Card('Unchecked', photo: firstPhoto),
          _Card('Nora James', photo: firstPhoto),
          const _Card('Boris Lane'),
          _Card('Alice Park', photo: secondPhoto),
        ]);
        var startedUploads = 0;
        await _withField(
          tester,
          _ContactPicker(file),
          (flow) async {
            try {
              await flow.openChecklist();
              expect(_toggleValue(tester, _usePhoto), isTrue);
              for (final name in ['Nora James', 'Boris Lane', 'Alice Park']) {
                await flow.tick(name);
              }
              await flow.submit(settle: false);
              await _pumpUntil(
                tester,
                () => flow.batches.isNotEmpty,
                'the batch request',
              );
              expect(
                flow.rows.map((row) => row['name']),
                unorderedEquals(['Nora James', 'Boris Lane', 'Alice Park']),
              );
              expect(flow.wire.uploads, isEmpty);

              batchReply.complete();
              await _pumpUntil(
                tester,
                () => flow.wire.uploads.isNotEmpty,
                'the first private upload',
              );
              await tester.pump(const Duration(milliseconds: 200));
              expect(
                flow.wire.uploads,
                hasLength(1),
                reason: 'The first HTTP reply is still pending',
              );
              firstUploadReply.complete();
              await _pumpUntil(
                tester,
                () => flow.wire.uploads.length >= 2,
                'the second private upload',
              );
              await _settle(tester);

              expect(flow.wire.uploads, hasLength(2));
              final uploadsById = {
                for (final call in flow.wire.uploads) _uploadId(call): call,
              };
              expect(
                uploadsById.keys,
                unorderedEquals([_createdId, _secondId]),
              );
              _expectPhoto(uploadsById[_createdId]!, red: true);
              _expectPhoto(uploadsById[_secondId]!, red: false);
            } finally {
              if (!batchReply.isCompleted) batchReply.complete();
              if (!firstUploadReply.isCompleted) firstUploadReply.complete();
            }
          },
          respond: (call) async {
            if (call.field == _batch) {
              await batchReply.future;
              return _batchResult(
                call,
                created: const {
                  'Alice Park': _secondId,
                  'Boris Lane': _noPhotoId,
                  'Nora James': _createdId,
                },
              );
            }
            if (call.field == _upload && ++startedUploads == 1) {
              await firstUploadReply.future;
            }
            return null;
          },
        );
      },
    );

    testWidgets(
      'a partial batch reply marks the created row and explains the refused row',
      (
        tester,
      ) async {
        final photo = _ContactFile.fixture('contact_photo.jpg').bytes;
        final file = _vCard([
          _Card('Unchecked', photo: photo),
          _Card('Nora James', photo: photo),
          _Card('Boris Lane', photo: photo),
        ]);
        await _withField(
          tester,
          _ContactPicker(file),
          (flow) async {
            await flow.openChecklist();
            await flow.tick('Nora James');
            await flow.tick('Boris Lane');
            await flow.submit();

            expect(
              flow.rows.map((row) => row['name']),
              unorderedEquals(['Nora James', 'Boris Lane']),
            );
            final mark = _mark(_onMap);
            expect(mark, findsOneWidget);
            expect(
              _rowFor(
                'Boris Lane',
                mark,
                others: const ['Nora James', 'Unchecked'],
              ),
              findsOneWidget,
            );
            expect(
              _rowFor(
                'Nora James',
                find.text(_capRefusal),
                others: const ['Boris Lane', 'Unchecked'],
              ),
              findsOneWidget,
            );
            expect(_uploadId(flow.wire.uploads.single), _createdId);
          },
          respond: (call) => call.field == _batch
              ? _batchResult(
                  call,
                  created: const {'Boris Lane': _createdId},
                  refused: const {'Nora James': _capRefusal},
                )
              : null,
        );
      },
    );

    for (final (language, capReached) in const [
      ('en', false),
      ('en', true),
      ('ru', false),
      ('ru', true),
    ]) {
      final result = capReached ? 'a refused row' : 'a successful import';
      testWidgets(
        'the $language contact import uses catalog copy through validation and $result',
        (
          tester,
        ) async {
          const existing = 'mIRA Lane';
          const corrected = 'Alex';
          const refused = 'Nora James';
          const noMatch = 'zzzz';
          final photo = _ContactFile.fixture('contact_photo.jpg').bytes;
          final file = _vCard([
            const _Card(existing),
            _Card(_shortName, photo: photo),
            const _Card(refused),
          ]);
          final batchReply = Completer<void>();
          final photoReply = Completer<void>();
          await _withField(
            tester,
            _ContactPicker(file),
            (flow) async {
              try {
                await flow.openAddPerson();
                final surroundingCopy = _displayedCopy();
                final copy = _ImportCopy(language);
                final usersAndFile = {
                  existing,
                  _shortName,
                  corrected,
                  refused,
                  noMatch,
                  file.name,
                };
                void checkCopy(String stage) {
                  copy.expectLocalized(
                    _displayedCopy()
                        .difference(surroundingCopy)
                        .difference(usersAndFile),
                    stage: stage,
                    fixtureValues: usersAndFile,
                  );
                  expect(find.bySemanticsLabel(_internalName), findsNothing);
                }

                await flow.openPicker(
                  label: copy.label(_entry),
                  fromAddPerson: true,
                );
                final options = _englishOptions.map(copy.label).toList();
                final importLabel = copy.label(_import);
                final mapMark = _mark(copy.label(_onMap));
                for (final label in [...options, importLabel]) {
                  expect(find.text(label), findsOneWidget);
                }
                expect(
                  _rowFor(
                    existing,
                    mapMark,
                    others: const [_shortName, refused],
                  ),
                  findsOneWidget,
                );
                final search = _searchField(russian: language == 'ru');
                expect(search, findsOneWidget);
                checkCopy('initial checklist');
                for (final label in options) {
                  await _tap(tester, _toggle(label));
                  checkCopy('changed privacy option');
                  await _tap(tester, _toggle(label));
                }

                await tester.enterText(search, noMatch);
                await _settle(tester);
                expect(_contactLabel(refused), findsNothing);
                checkCopy('search with no matching contacts');
                await tester.enterText(search, '');
                await _settle(tester);

                await _tap(tester, _contactCheck(_shortName, options: options));
                final editingMark = _editingMark(russian: language == 'ru');
                expect(
                  _rowFor(
                    _shortName,
                    editingMark,
                    others: const [existing, refused],
                  ),
                  findsOneWidget,
                );
                expect(_importButton(label: importLabel).onPressed, isNull);
                checkCopy('selected short name');
                await _editName(
                  tester,
                  _shortName,
                  corrected,
                  editTooltip: () => copy.label('Edit name'),
                  afterOpen: () => checkCopy('name editor'),
                );
                expect(_contactLabel(corrected), findsOneWidget);
                expect(
                  _rowFor(
                    corrected,
                    editingMark,
                    others: const [existing, refused],
                  ),
                  findsNothing,
                );
                checkCopy('corrected name');
                await _tap(tester, _contactCheck(refused, options: options));

                await flow.submit(label: importLabel, settle: false);
                await _pumpUntil(
                  tester,
                  () => flow.batches.isNotEmpty,
                  'the pending import request',
                );
                checkCopy('import in progress');
                batchReply.complete();
                await _pumpUntil(
                  tester,
                  () => flow.wire.uploads.isNotEmpty,
                  'the pending private avatar upload',
                );
                checkCopy('photo upload in progress');
                photoReply.complete();
                await _settle(tester);

                expect(_uploadId(flow.wire.uploads.single), _createdId);
                if (capReached) {
                  final refusal = find.text(copy.label(_capRefusal));
                  expect(
                    _rowFor(
                      refused,
                      refusal,
                      others: const [existing, corrected],
                    ),
                    findsOneWidget,
                  );
                  expect(
                    _rowFor(
                      corrected,
                      mapMark,
                      others: const [existing, refused],
                    ),
                    findsOneWidget,
                  );
                }
                if (language == 'ru') {
                  expect(find.text(_capRefusal), findsNothing);
                }
                checkCopy(result);
              } finally {
                if (!batchReply.isCompleted) batchReply.complete();
                if (!photoReply.isCompleted) photoReply.complete();
              }
            },
            respond: (call) async {
              if (call.field == _batch) {
                await batchReply.future;
                return _batchResult(
                  call,
                  created: {
                    corrected: _createdId,
                    if (!capReached) refused: _secondId,
                  },
                  refused: {if (capReached) refused: _capRefusal},
                );
              }
              if (call.field == _upload) await photoReply.future;
              return null;
            },
            locale: Locale(language),
          );
        },
      );
    }

    test(
      'the import action, options, map status and refusal have matching catalog entries',
      () {
        final copy = _ImportCopy('ru');
        final labels = [
          _entry,
          _import,
          ..._englishOptions,
          _onMap,
          _capRefusal,
        ];
        expect(
          labels.where((label) => copy._labelsFor(label).isEmpty),
          isEmpty,
          reason: 'Each label needs a shared catalog key and Russian copy',
        );
      },
    );
  });
}

FieldNode _selectedField(SelectionSetNode selection, String name) => selection
    .selections
    .whereType<FieldNode>()
    .singleWhere((field) => field.name.value == name);

Object? _matchAnswer(PhantomImportCreated outcome) {
  try {
    return (outcome as dynamic).alreadyOnTentura as bool?;
    // Report a missing answer separately from a genuine null response.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return 'no match answer in the saved outcome';
  }
}

void _expectSavedRow(
  WidgetTester tester,
  String name,
  L10n l10n, {
  required List<String> others,
}) {
  final options = [l10n.contactImportUsePhoto, l10n.contactImportKeepDetails];
  final checkbox = _contactCheck(name, options: options);
  expect(checkbox, findsOneWidget);
  expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
  expect(
    _rowFor(
      name,
      find.text(l10n.contactImportOnMap),
      others: others.where((other) => other != name).toList(),
    ),
    findsOneWidget,
  );
}

void _expectPublicCopySince(Set<String> before) {
  expect(
    _displayedCopy().difference(before).where(_internalContactTerms.hasMatch),
    isEmpty,
  );
}

Future<void> _withField(
  WidgetTester tester,
  _ContactPicker picker,
  Future<void> Function(_ImportFlow) scenario, {
  FutureOr<Object?> Function(AvatarWireCall)? respond,
  Locale locale = const Locale('en'),
}) async {
  final previousPicker = FilePickerPlatform.instance;
  FilePickerPlatform.instance = picker;
  addTearDown(() => FilePickerPlatform.instance = previousPicker);
  final wire = PrivateAvatarWire(
    accountlessDisplayName: '  Mira Lane  ',
    contacts: const {accountHolderId: '  Sam Reed  '},
    responseFor: (call) async {
      final custom = await respond?.call(call);
      if (custom != null) return custom;
      switch (call.field) {
        case 'personTags':
        case 'personAutoTags':
        case 'personTagMemberships':
          return <Object?>[];
        case _batch:
          final rows = _submittedRows(call);
          return _batchResult(
            call,
            created: {
              for (final (index, row) in rows.indexed)
                row['name']! as String:
                    'PH${(index + 1).toString().padLeft(12, '0')}',
            },
          );
        case _upload:
          return true;
        default:
          return null;
      }
    },
  );

  await wire.run((remote) async {
    final realtime = buildTestRealtimeSync();
    addTearDown(realtime.port.dispose);
    final fixture = ConstellationStoreFixture(
      ConstellationRepository(remote),
      accountId: avatarViewer.id,
      clock: FakeClockPort(avatarFixtureTime),
      wakeUp: FakeWakeUpPort(),
      realtime: realtime.case_,
    );
    final cubit = fixture.createCubit(viewer: avatarViewer);
    final tags = PeopleTagsCase(
      PeopleTagsRepository(remote),
      realtime.case_,
      env: const Env(),
      logger: Logger.detached('ContactImportTagsTest'),
    );
    addTearDown(tags.dispose);
    GetIt.I.pushNewScope(
      init: (scope) => scope
        ..registerSingleton<RemoteApiService>(remote)
        ..registerSingleton<RemoteRequestClient>(remote)
        ..registerSingleton<ConstellationFieldStoreCase>(fixture.store)
        ..registerSingleton<PeopleTagsCase>(tags)
        ..registerSingleton<PhantomRepositoryPort>(PhantomRepository(remote)),
    );
    addTearDown(GetIt.I.popScope);
    await tags.load().timeout(const Duration(seconds: 4));
    await cubit.load().timeout(const Duration(seconds: 4));
    expect(cubit.state.loadError, isNull);
    expect(
      cubit.state.field?.phantoms.map((person) => person.id),
      contains(accountlessId),
    );
    expect(cubit.state.field?.directContactIds, contains(accountHolderId));
    final phone = locale.languageCode == 'ru';
    if (phone) await usePhoneSurface(tester);
    final composer = buildComposerHarnessComposer(eligible: const {});
    await pumpConstellationBody(
      tester,
      cubit,
      size: phone ? kPhoneSurface : const Size(1200, 900),
      locale: locale,
      disableAnimations: true,
      wrapBody: (body) => BlocProvider<ConstellationComposerCubit>.value(
        value: composer,
        child: Scaffold(
          body: Column(
            children: [
              ConstellationAppBarRow(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
    try {
      await _settle(tester);
      await scenario(_ImportFlow(tester, picker, wire, locale));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

class _ImportFlow {
  _ImportFlow(this.tester, this.picker, this.wire, this.locale);

  final WidgetTester tester;
  final _ContactPicker picker;
  final PrivateAvatarWire wire;
  final Locale locale;

  List<AvatarWireCall> get batches =>
      wire.calls.where((call) => call.field == _batch).toList();

  List<Map<String, Object?>> get rows => _submittedRows(batches.single);

  Future<void> openAddPerson() async {
    final label = lookupL10n(locale).personCreateAction;
    final item = find.descendant(
      of: find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
      matching: find.text(label),
    );
    await _tap(
      tester,
      find.byKey(const Key('constellation.app_bar.create_here')),
    );
    await _tap(tester, item);
  }

  Future<void> openPicker({
    String label = _entry,
    bool fromAddPerson = false,
  }) async {
    if (!fromAddPerson) await openAddPerson();
    expect(picker.requests, isEmpty);
    final action = find.text(label);
    expect(
      action,
      findsOneWidget,
      reason: '+ Person offers contact-file import',
    );
    await _tap(tester, action);

    expect(picker.requests, hasLength(1));
    expect(picker.requests.single.type, FileType.custom);
    expect(picker.requests.single.extensions, unorderedEquals(['vcf', 'csv']));
    expect(
      batches,
      isEmpty,
      reason: 'The file stays on the device until Import',
    );
  }

  Future<void> openChecklist({bool fromAddPerson = false}) async {
    await openPicker(fromAddPerson: fromAddPerson);
    expect(_searchField(), findsOneWidget);
    expect(find.textContaining(_internalName), findsNothing);
    expect(find.bySemanticsLabel(_internalName), findsNothing);
  }

  Future<void> tick(String name) => _tap(tester, _contactCheck(name));

  Future<void> submit({String label = _import, bool settle = true}) async {
    expect(_importButton(label: label).onPressed, isNotNull);
    await _tap(tester, find.text(label), settle: settle);
    if (!settle) return;
    expect(batches, hasLength(1));
    expect(batches.single.isMutation, isTrue);
    expect(batches.single.path, '/api/v2/graphql');
  }
}

List<Map<String, Object?>> _submittedRows(AvatarWireCall call) =>
    (call.variables['rows']! as List<Object?>).cast<Map<String, Object?>>();

// As on the server, rowIndex is relative to the submitted rows. Returning
// created entries out of order catches callers that zip the two lists.
Map<String, Object?> _batchResult(
  AvatarWireCall call, {
  required Map<String, String> created,
  Map<String, String> refused = const {},
  Map<String, bool?> matchAnswers = const {},
}) {
  final indices = {
    for (final (index, row) in _submittedRows(call).indexed)
      row['name']! as String: index,
  };
  return {
    '__typename': 'PhantomImportResult',
    'created': [
      for (final entry in created.entries)
        {
          '__typename': 'PhantomImportCreated',
          'rowIndex':
              indices[entry.key] ??
              (throw StateError('No submitted contact named ${entry.key}')),
          'id': entry.value,
          if (matchAnswers.containsKey(entry.key))
            'alreadyOnTentura': matchAnswers[entry.key],
        },
    ],
    'refused': [
      for (final entry in refused.entries)
        {
          '__typename': 'PhantomImportRefused',
          'rowIndex': indices[entry.key]!,
          'message': entry.value,
        },
    ],
  };
}

String _uploadId(AvatarWireCall call) {
  expect(call.path, '/api/v2/graphql');
  expect(call.isMutation, isTrue);
  expect(call.variables['subjectUserId'], isNull);
  expect(
    call.file,
    isNotEmpty,
    reason: 'The photo is sent in the multipart upload',
  );
  return call.variables['subjectPhantomId']! as String;
}

Uint8List _jpeg(img.ColorRgb8 color) =>
    img.encodeJpg(img.Image(width: 8, height: 8)..clear(color));

void _expectPhoto(AvatarWireCall upload, {required bool red}) {
  final pixel = img.decodeJpg(Uint8List.fromList(upload.file!))!.getPixel(0, 0);
  expect(pixel.r.compareTo(pixel.b), red ? isPositive : isNegative);
}

class _ContactPicker extends FilePickerPlatform {
  _ContactPicker(this.file);

  final _ContactFile? file;
  final requests = <({FileType type, List<String>? extensions})>[];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requests.add((type: type, extensions: allowedExtensions));
    return [?file];
  }
}

final class _ContactFile extends PlatformFile {
  _ContactFile(this.name, List<int> content)
    : bytes = Uint8List.fromList(content);

  _ContactFile.fixture(String name)
    : this(name, File('$_fixturePath/$name').readAsBytesSync());

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.dataFromBytes(bytes);
  @override
  XFile get xFile => XFile.fromData(bytes, name: name);
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _Card {
  const _Card(this.name, {this.email, this.phone, this.photo});

  final String name;
  final String? email;
  final String? phone;
  final Uint8List? photo;
}

_ContactFile _names(List<String> names) => _vCard([
  for (final name in names) _Card(name),
]);

_ContactFile _vCard(List<_Card> cards) => _ContactFile(
  'contacts.vcf',
  utf8.encode(
    [
      for (final card in cards) ...[
        'BEGIN:VCARD',
        'VERSION:3.0',
        'FN:${card.name}',
        if (card.email case final email?) 'EMAIL:$email',
        if (card.phone case final phone?) 'TEL:$phone',
        if (card.photo case final photo?)
          'PHOTO;ENCODING=b;TYPE=JPEG:${base64Encode(photo)}',
        'END:VCARD',
      ],
    ].join('\r\n'),
  ),
);

Finder _contactLabel(String name) => find.textContaining(
  RegExp('^\\s*${RegExp.escape(name)}\\s*\$'),
);

Finder _mark(String label) => find.textContaining(
  RegExp('^${RegExp.escape(label)}\\.?\$', caseSensitive: false),
);

Finder _contactCheck(String name, {List<String> options = _englishOptions}) =>
    _controlByLabel(_contactLabel(name), _rowChecks(options));

bool? _selected(WidgetTester tester, String name) =>
    tester.widget<Checkbox>(_contactCheck(name)).value;

// A status belongs to a contact when the smallest branch that contains both
// excludes the other contact labels. A marked row can omit its checkbox.
Finder _rowFor(String name, Finder status, {required List<String> others}) {
  final otherLabels = others
      .expand((other) => _contactLabel(other).evaluate())
      .toSet();
  final otherContacts = find.byElementPredicate(otherLabels.contains);
  final rows = <Element>{};
  for (final label in _contactLabel(name).evaluate()) {
    label.visitAncestorElements((ancestor) {
      final branch = find.byElementPredicate(
        (element) => identical(element, ancestor),
      );
      if (find
          .descendant(of: branch, matching: otherContacts)
          .evaluate()
          .isNotEmpty) {
        return false;
      }
      if (find.descendant(of: branch, matching: status).evaluate().isEmpty) {
        return true;
      }
      rows.add(ancestor);
      return false;
    });
  }
  return find.byElementPredicate(
    rows.contains,
    description: 'the $name row with $status',
  );
}

const _englishOptions = [_usePhoto, _keepDetails];

Finder _rowChecks([List<String> options = _englishOptions]) {
  final optionControls = options
      .expand((label) => _toggle(label).evaluate())
      .toSet();
  return find.byElementPredicate(
    (element) =>
        element.widget is Checkbox && !optionControls.contains(element),
    description: 'contact row checkbox',
  );
}

Finder _toggle(String label) => _controlByLabel(
  find.text(label),
  find.byWidgetPredicate((widget) => widget is Switch || widget is Checkbox),
);

bool? _toggleValue(WidgetTester tester, String label) =>
    switch (tester.widget(_toggle(label))) {
      Switch(:final value) => value,
      Checkbox(:final value) => value,
      _ => throw StateError('No toggle for $label'),
    };

// Associate the label and its control by their nearest common branch. This
// works for Material list tiles and for a row with a separate label and control.
Finder _controlByLabel(Finder label, Finder controls) {
  final matchingControls = <Element>{};
  for (final element in label.evaluate()) {
    element.visitAncestorElements((ancestor) {
      final found = find
          .descendant(
            of: find.byElementPredicate(
              (candidate) => identical(candidate, ancestor),
            ),
            matching: controls,
          )
          .evaluate()
          .toList();
      if (found.isEmpty) return true;
      if (found.length == 1) matchingControls.add(found.single);
      return false;
    });
  }
  return find.byElementPredicate(
    matchingControls.contains,
    description: 'control for $label',
  );
}

Finder _editingMark({bool russian = false}) => find.byWidgetPredicate((widget) {
  final text = switch (widget) {
    Text() => widget.data ?? widget.textSpan?.toPlainText(),
    TextField() => widget.decoration?.errorText,
    _ => null,
  };
  return text != null &&
      (russian ? _russianEditingNeeded : _editingNeeded).hasMatch(text);
}, description: 'short-name editing indication');

Iterable<String> _inputLabels(Widget widget) => switch (widget) {
  TextField() => [
    widget.decoration?.labelText,
    widget.decoration?.hintText,
  ].whereType<String>(),
  SearchBar() => [widget.hintText].whereType<String>(),
  _ => const [],
};

Finder _searchField({bool russian = false}) {
  final search = RegExp(
    russian ? 'поиск|искать|найти' : 'search',
    caseSensitive: false,
  );
  return find.byWidgetPredicate(
    (widget) => _inputLabels(widget).any(search.hasMatch),
    description: 'contact search field',
  );
}

ButtonStyleButton _importButton({String label = _import}) =>
    find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            )
            .evaluate()
            .single
            .widget
        as ButtonStyleButton;

Future<void> _editName(
  WidgetTester tester,
  String current,
  String name, {
  String Function()? editTooltip,
  VoidCallback? afterOpen,
}) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller.text == current,
    description: '$current name editor',
  );
  if (field.evaluate().isEmpty) {
    await _tap(tester, find.byTooltip(editTooltip?.call() ?? 'Edit name'));
    afterOpen?.call();
  }
  expect(field, findsOneWidget);
  await tester.ensureVisible(field);
  await tester.enterText(field, name);
  await _settle(tester);
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  if (settle) await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 4),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String event,
) async {
  for (var i = 0; i < 20 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'Expected $event');
}

final _copyLetters = RegExp('[A-Za-zА-Яа-яЁё]');
final _cyrillic = RegExp('[А-Яа-яЁё]');
final _productAndFormats = RegExp(
  r'^(?:Tentura|CSV|VCF|vCard)(?:[ /,]+(?:Tentura|CSV|VCF|vCard))*$',
);

String _normalizeCopy(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

Set<String> _displayedCopy() {
  final copy = <String>{};
  void add(String? text) {
    if (text != null && _copyLetters.hasMatch(text)) {
      copy.add(_normalizeCopy(text));
    }
  }

  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget is RichText ||
                widget is Tooltip ||
                widget is TextField ||
                widget is SearchBar ||
                widget is Semantics,
          )
          .evaluate()) {
    switch (element.widget) {
      case final RichText text:
        add(text.text.toPlainText(includeSemanticsLabels: false));
      case final Tooltip tooltip:
        add(tooltip.message ?? tooltip.richMessage?.toPlainText());
      case final TextField field:
        add(field.decoration?.labelText);
        add(field.decoration?.hintText);
        add(field.decoration?.helperText);
        add(field.decoration?.errorText);
      case final SearchBar search:
        add(search.hintText);
      case final Semantics semantics:
        add(semantics.properties.label);
        add(semantics.properties.hint);
        add(semantics.properties.tooltip);
    }
  }
  return copy;
}

Map<String, Object?> _catalog(String language) =>
    jsonDecode(File('l10n/app_$language.arb').readAsStringSync())
        as Map<String, Object?>;

class _ImportCopy {
  _ImportCopy(this.language);

  final String language;
  final _english = _catalog('en');
  final _russian = _catalog('ru');
  final _checked = <String, bool>{};

  Iterable<String> get _keys =>
      _english.keys.where((key) => !key.startsWith('@'));

  String label(String english) {
    final localized = _labelsFor(english);
    expect(
      localized,
      hasLength(1),
      reason: 'A shared key translates "$english"',
    );
    return localized.single;
  }

  Set<String> _labelsFor(String expected) {
    final localized = <String>{};
    for (final key in _keys) {
      final en = _english[key];
      final ru = _russian[key];
      if (en is String &&
          en.toLowerCase() == expected.toLowerCase() &&
          ru is String &&
          _publicRussian(ru)) {
        localized.add(language == 'ru' ? ru : en);
      }
    }
    return localized;
  }

  void expectLocalized(
    Set<String> displayed, {
    required String stage,
    required Set<String> fixtureValues,
  }) {
    final missing = displayed.where(
      (text) => !_checked.putIfAbsent(
        text,
        () =>
            !_internalName.hasMatch(text) &&
            (language != 'ru' || _publicRussian(text)) &&
            _hasTranslation(text, fixtureValues),
      ),
    );
    expect(
      missing,
      isEmpty,
      reason:
          '$language $stage copy must come from matching en and ru ARB entries',
    );
  }

  bool _hasTranslation(String shown, Set<String> fixtureValues) {
    final strings = language == 'ru' ? _russian : _english;
    for (final key in _keys) {
      final en = _english[key];
      final ru = _russian[key];
      if (en is! String ||
          ru is! String ||
          en.trim().isEmpty ||
          _internalName.hasMatch(en) ||
          !_publicRussian(ru)) {
        continue;
      }
      final template = strings[key]! as String;
      if (_normalizeCopy(template) == shown) return true;
      final argumentStart = template.indexOf('{');
      if (argumentStart < 0 ||
          !shown.startsWith(
            _normalizeCopy(template.substring(0, argumentStart)),
          )) {
        continue;
      }
      final metadata = _english['@$key'] as Map<String, dynamic>?;
      final placeholders = metadata?['placeholders'] as Map<String, dynamic>?;
      if (placeholders == null || placeholders.isEmpty) continue;
      final numbers = <int>{
        0,
        1,
        2,
        3,
        32,
        200,
        for (final match in RegExp(r'\d+').allMatches(shown))
          int.parse(match[0]!),
      };
      final format = MessageFormat(template, locale: language);
      for (final args in _messageArguments(
        placeholders.entries.toList(),
        numbers,
        fixtureValues,
      )) {
        if (_normalizeCopy(format.format(args)) == shown) {
          final counterpart = language == 'ru'
              ? MessageFormat(en).format(args)
              : MessageFormat(ru, locale: 'ru').format(args);
          if (language == 'ru'
              ? counterpart.trim().isNotEmpty &&
                    !_internalName.hasMatch(counterpart)
              : _publicRussian(counterpart)) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

bool _publicRussian(String text) =>
    !_internalName.hasMatch(text) &&
    (_cyrillic.hasMatch(text) || _productAndFormats.hasMatch(text));

// Render actual ICU messages using the values this fixture can display. An
// arbitrary wildcard could incorrectly match a hardcoded untranslated label.
Iterable<Map<String, Object>> _messageArguments(
  List<MapEntry<String, dynamic>> placeholders,
  Set<int> numbers,
  Set<String> fixtureValues,
) sync* {
  if (placeholders.isEmpty) {
    yield {};
    return;
  }
  final placeholder = placeholders.first;
  final type = (placeholder.value as Map<String, dynamic>)['type'];
  final values = switch (type) {
    'int' || 'num' || 'double' => numbers,
    'String' => fixtureValues,
    null || 'Object' => <Object>{...numbers, ...fixtureValues},
    _ => const <Object>[],
  };
  for (final rest in _messageArguments(
    placeholders.sublist(1),
    numbers,
    fixtureValues,
  )) {
    for (final value in values) {
      yield {placeholder.key: value, ...rest};
    }
  }
}
