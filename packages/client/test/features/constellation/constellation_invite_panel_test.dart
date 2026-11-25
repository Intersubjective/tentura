@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_field_search_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_search_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/ui/widget/adaptive_context_overlay.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _anna = 'PH0123456789ab';
const _annaName = 'Anna K.';
const _fieldPerson = 'Ufield0000001';
const _directoryPerson = 'Uoutside00001';
const _fieldPersonName = 'Jamie Field';
const _directoryPersonName = 'Morgan Directory';
const _otherEntryName = 'Cleo Private';
const _originalCode = 'I123456789abc';
const _rotatedCode = 'I987654321abc';
const _copy = 'Copy invite link';
const _rotate = 'New link';
const _link = 'This is someone already on Tentura…';
const _remove = 'Remove from my map';
const _status = 'Not on Tentura yet';
const _liveStatus = '$_status · invite sent 3 days ago';
const _tags = {
  'Tgardening001': 'Gardening',
  'Tneighbours01': 'Neighbours',
  'Tbooks0000001': 'Book club',
};
final _now = DateTime.utc(2026, 11, 25, 12);
final _inviteCreatedAt = _now.subtract(const Duration(days: 3, hours: 20));

Finder get _panel => find.byType(AdaptiveContextOverlay);

Finder _text(String value) => find.text(value, findRichText: true);

Finder _inPanel(Finder child) => find.descendant(of: _panel, matching: child);

Finder get _annaMarker => find.byKey(const ValueKey('fh:$_anna'));

void main() {
  group('Field panel for someone without an account', () {
    testWidgets(
      'shows the name and whole days since the live invite was sent',
      (
        tester,
      ) async {
        await _withField(tester, (_) async {
          expect(_text(_liveStatus), findsNothing);
          await _openAnna(tester);
          expect(_text(_liveStatus), findsOneWidget);
          expect(_inPanel(_text('Anna K.')), findsOneWidget);
        });
      },
    );

    testWidgets('shows only the account status when there is no invite', (
      tester,
    ) async {
      await _withField(tester, (_) async {
        await _openAnna(tester);
        expect(_inPanel(_text(_status)), findsOneWidget);
        expect(
          find.textContaining('invite sent', findRichText: true),
          findsNothing,
        );
      }, live: false);
    });

    testWidgets('shows the two assigned tags from the owner’s catalog', (
      tester,
    ) async {
      await _withField(tester, (_) async {
        await _openAnna(tester);
        expect(_inPanel(_text('Gardening')), findsOneWidget);
        expect(_inPanel(_text('Neighbours')), findsOneWidget);
        expect(_inPanel(_text('Book club')), findsNothing);
      }, tagged: true);
    });

    testWidgets('shows no tag chips for an untagged person', (tester) async {
      await _withField(tester, (_) async {
        await _openAnna(tester);
        expect(_inPanel(_text('Anna K.')), findsOneWidget);
        for (final tag in _tags.values) {
          expect(_inPanel(_text(tag)), findsNothing);
        }
      });
    });

    testWidgets('copies the invite link for the selected person', (
      tester,
    ) async {
      await _withField(tester, (wire) async {
        await _openAnna(tester);
        await _tap(tester, _text(_copy));
        expect(wire.variablesFor('PhantomInviteEnsure'), [
          {'id': _anna},
        ]);
        expect(wire.clipboard.map(_invitePath), ['/invite/$_originalCode']);
      }, live: false);
    });

    testWidgets('a new link replaces the previous invite link', (tester) async {
      await _withField(tester, (wire) async {
        await _openAnna(tester);
        await _tap(tester, _text(_rotate));
        expect(wire.variablesFor('PhantomInviteRotate'), [
          {'id': _anna},
        ]);
        final offered = find.textContaining(
          '/invite/$_rotatedCode',
          findRichText: true,
        );
        if (wire.clipboard.isEmpty && offered.evaluate().isEmpty) {
          await _tap(tester, _text(_copy));
        }
        expect(
          find.textContaining('/invite/$_originalCode', findRichText: true),
          findsNothing,
        );
        if (wire.clipboard.isEmpty) {
          expect(offered, findsOneWidget);
        } else {
          expect(wire.clipboard.map(_invitePath), ['/invite/$_rotatedCode']);
        }
      });
    });

    testWidgets('offers only real Field people for manual linking', (
      tester,
    ) async {
      await _withField(tester, (wire) async {
        await _openAnna(tester);
        await _tap(tester, _text(_link));
        final eligiblePerson = await _checkLinkPickerResults(tester);
        expect(wire.variablesFor('PhantomLink'), isEmpty);
        await _tap(tester, eligiblePerson);
        expect(wire.variablesFor('PhantomLink'), [
          {'phantomId': _anna, 'userId': _fieldPerson},
        ]);
      });
    });

    testWidgets('cancel closes the removal confirmation and keeps the person', (
      tester,
    ) async {
      await _withField(tester, (wire) async {
        await _openAnna(tester);
        await _requestRemoval(tester, _remove);
        expect(wire.variablesFor('PhantomDelete'), isEmpty);
        await _tap(tester, _dialogText('Cancel'));
        expect(_removalDialog, findsNothing);
        expect(wire.variablesFor('PhantomDelete'), isEmpty);
        expect(_inPanel(_text('Anna K.')), findsOneWidget);
        expect(_annaMarker, findsOneWidget);
      });
    });

    testWidgets('confirming removal deletes the selected person once', (
      tester,
    ) async {
      await _withField(tester, (wire) async {
        await _openAnna(tester);
        await _requestRemoval(tester, _remove);
        expect(wire.variablesFor('PhantomDelete'), isEmpty);
        await _tap(tester, _dialogText('Remove'));
        expect(wire.variablesFor('PhantomDelete'), [
          {'id': _anna},
        ]);
        expect(_removalDialog, findsNothing);
      });
    });

    for (final (action, operation) in [
      (_copy, 'PhantomInviteEnsure'),
      (_rotate, 'PhantomInviteRotate'),
      (_link, 'PhantomLink'),
      (_remove, 'PhantomDelete'),
    ]) {
      testWidgets(
        'keeps Anna’s panel open if $action is rejected while she joins',
        (
          tester,
        ) async {
          await _withField(
            tester,
            (wire) async {
              await _openAnna(tester);
              if (action == _remove) {
                await _requestRemoval(tester, _remove);
                await _tap(tester, _dialogText('Remove'));
              } else {
                await _tap(tester, _text(action));
                if (action == _link) {
                  await _tap(tester, _text(_fieldPersonName).hitTestable());
                }
              }
              expect(wire.variablesFor(operation), [
                if (action == _link)
                  {'phantomId': _anna, 'userId': _fieldPerson}
                else
                  {'id': _anna},
              ]);
              expect(
                find.textContaining(
                  RegExp(r'^Anna is joining right now\.?$'),
                  findRichText: true,
                ),
                findsOneWidget,
              );
              expect(_inPanel(_text('Anna')), findsOneWidget);
              expect(_inPanel(_text(_liveStatus)), findsOneWidget);
              expect(_inPanel(_text('Gardening')), findsOneWidget);
              expect(_inPanel(_text('Neighbours')), findsOneWidget);
              expect(_inPanel(_text(action)), findsOneWidget);
              expect(_annaMarker, findsOneWidget);
              expect(wire.clipboard, isEmpty);
            },
            name: 'Anna',
            tagged: true,
            reject: operation,
          );
        },
      );
    }

    testWidgets(
      'shows Russian status, actions, confirmation and error on a phone',
      (
        tester,
      ) async {
        await _withField(
          tester,
          (wire) async {
            await _openAnna(tester);
            expect(_inPanel(_text('Anna')), findsOneWidget);
            final copy = _PanelCopy();
            expect(_inPanel(_text(copy.russianLiveStatus)), findsOneWidget);
            for (final action in [_copy, _rotate, _link, _remove]) {
              expect(_inPanel(_text(copy.russian(action))), findsOneWidget);
            }

            await _requestRemoval(tester, copy.russian(_remove));
            final dialog = tester.widget<AlertDialog>(_removalDialog);
            final message = <String>[
              for (final part in [dialog.title, dialog.content])
                if (part is Text) ?part.data,
            ];
            expect(message, isNotEmpty);
            expect(message, everyElement(isIn(copy.renderedRussianMessages)));
            expect(
              message.any((line) => RegExp('[А-Яа-яЁё]').hasMatch(line)),
              isTrue,
            );
            expect(_dialogText(copy.ru['buttonCancel']!), findsOneWidget);
            await _tap(tester, _dialogText(copy.ru['buttonRemove']!));
            expect(wire.variablesFor('PhantomDelete'), [
              {'id': _anna},
            ]);
            expect(_text(copy.russianJoiningError), findsOneWidget);
            expect(_inPanel(_text('Anna')), findsOneWidget);
            expect(_inPanel(_text(copy.russianLiveStatus)), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
          name: 'Anna',
          locale: const Locale('ru'),
          reject: 'PhantomDelete',
        );
      },
    );
  });

  test('English and Russian catalogs translate the panel in public terms', () {
    final copy = _PanelCopy();
    final internalTerm = RegExp('phantom|фантом', caseSensitive: false);
    for (final (locale, catalog) in [('en', copy.en), ('ru', copy.ru)]) {
      expect(
        catalog.entries.where((entry) => internalTerm.hasMatch(entry.value)),
        isEmpty,
        reason: 'User-facing $locale messages use public terminology',
      );
    }
    expect(copy.ru.keys, unorderedEquals(copy.en.keys));
    for (final action in [_status, _copy, _rotate, _link, _remove]) {
      expect(copy.russian(action), matches(RegExp('[А-Яа-яЁё]')));
    }
    expect(copy.russianLiveStatus, matches(RegExp('[А-Яа-яЁё].*3')));
    expect(
      copy.russianJoiningError,
      allOf(contains('Anna'), matches(RegExp('[А-Яа-яЁё]'))),
    );
  });
}

Future<void> _openAnna(WidgetTester tester) async {
  final marker = _annaMarker.hitTestable();
  expect(marker, findsOneWidget, reason: 'Anna arrived on the Field');
  await tester.tap(marker);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<Finder> _checkLinkPickerResults(WidgetTester tester) async {
  final visiblePerson = _text(_fieldPersonName).hitTestable();
  expect(visiblePerson, findsOneWidget);
  final list = Scrollable.maybeOf(tester.element(visiblePerson));
  final results = list == null
      ? find.ancestor(
          of: visiblePerson,
          matching: find.byWidgetPredicate(
            (widget) => widget is Dialog || widget is BottomSheet,
          ),
        )
      : find.byElementPredicate(
          (element) => identical(element, list.context),
          description: 'manual-link result list',
        );
  expect(results, findsOneWidget);

  Finder resultNamed(String name) =>
      find.descendant(of: results, matching: _text(name));

  void expectOnlyEligiblePeople() {
    for (final name in [_directoryPersonName, _otherEntryName, _annaName]) {
      expect(resultNamed(name), findsNothing, reason: '$name is ineligible');
    }
  }

  if (list == null) {
    expectOnlyEligiblePeople();
    return resultNamed(_fieldPersonName);
  }

  // Visit each part of the list so lazily built, off-screen rows are checked.
  final position = list.position;
  final initialOffset = position.pixels;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  for (var page = 0; page < 20; page++) {
    expectOnlyEligiblePeople();
    if (position.pixels >= position.maxScrollExtent) {
      position.jumpTo(initialOffset);
      await tester.pumpAndSettle();
      return resultNamed(_fieldPersonName);
    }
    expect(position.viewportDimension, greaterThan(0));
    final next = position.pixels + position.viewportDimension / 2;
    position.jumpTo(
      next.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  fail('The picker did not reach the end of its results');
}

Finder get _removalDialog => find.bySubtype<AlertDialog>();

Finder _dialogText(String label) =>
    find.descendant(of: _removalDialog, matching: _text(label));

Future<void> _requestRemoval(WidgetTester tester, String label) async {
  await _tap(tester, _text(label));
  expect(_removalDialog, findsOneWidget);
}

String _invitePath(String text) {
  final uri = Uri.parse(text);
  expect(uri.scheme, anyOf('http', 'https'));
  expect(uri.host, isNotEmpty);
  return uri.path;
}

class _PanelCopy {
  final en = _catalog('en');
  final ru = _catalog('ru');

  String russian(String english) =>
      _translation((value) => value == english, english);

  String get russianLiveStatus {
    bool hasAge(String value) =>
        value.contains('invite sent') && value.contains('ago');
    final template = _translation(hasAge, 'the invite age');
    final age = _renderRussian(template);
    return en.values.any((value) => value.startsWith(_status) && hasAge(value))
        ? age
        : '${russian(_status)} · $age';
  }

  String get russianJoiningError => _renderRussian(
    _translation(
      (value) => value.contains(' is joining right now'),
      'the joining message',
    ),
  );

  Iterable<String> get renderedRussianMessages =>
      ru.values.map(_renderRussian).where((value) => !value.contains('{'));

  String _translation(bool Function(String) match, String description) {
    final keys = en.entries
        .where((entry) => match(entry.value))
        .map(
          (entry) => entry.key,
        );
    expect(keys, isNotEmpty, reason: 'The catalog includes $description');
    final values = [
      for (final key in keys) ru[key],
    ];
    expect(
      values,
      everyElement(
        isA<String>().having((v) => v.isNotEmpty, 'has copy', isTrue),
      ),
    );
    final distinct = values.cast<String>().toSet();
    expect(
      distinct,
      hasLength(1),
      reason: 'Russian translation for $description',
    );
    return distinct.single;
  }
}

Map<String, String> _catalog(String locale) {
  final json =
      jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
          as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in json.entries)
      if (!key.startsWith('@') && value is String) key: value,
  };
}

// These messages use a name and, for the invite age, a count of three days.
String _renderRussian(String template) {
  const days = 3;
  final plural = RegExp(r'\{\s*(\w+)\s*,\s*plural\s*,').firstMatch(template);
  if (plural != null) {
    final branches = RegExp(r'(=\d+|\w+)\s*\{((?:[^{}]|\{\w+\})*)\}\s*');
    final options = <String, String>{};
    var end = plural.end;
    for (final branch in branches.allMatches(template, end)) {
      if (template.substring(end, branch.start).trim().isNotEmpty) break;
      options[branch[1]!] = branch[2]!;
      end = branch.end;
    }
    final other = options['other'];
    if (other == null || !template.startsWith('}', end)) return template;
    // Three uses the Russian "few" category.
    final selected = options['=$days'] ?? options['few'] ?? other;
    return template.replaceRange(
      plural.start,
      end + 1,
      selected.replaceAll('#', '$days').replaceAll('{${plural[1]}}', '$days'),
    );
  }
  return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
    final field = match[1]!.toLowerCase();
    return field.contains('day') || field == 'count' ? '$days' : 'Anna';
  });
}

class _Account implements ConstellationAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer.id);
}

Future<void> _withField(
  WidgetTester tester,
  Future<void> Function(_PanelWire) body, {
  String name = _annaName,
  bool tagged = false,
  bool live = true,
  Locale locale = const Locale('en'),
  String? reject,
}) async {
  final wire = _PanelWire(name: name, tagged: tagged, live: live);
  final messenger = tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        wire.clipboard.add(arguments['text']! as String);
      }
      return null;
    });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  await withRemoteWire(
    {},
    wire.sent,
    (remote) async {
      final realtime = buildTestRealtimeSync();
      final clock = FakeClockPort(_now);
      final effects = FakeUiEffectPort();
      final peopleTags = PeopleTagsCase(
        PeopleTagsRepository(remote),
        realtime.case_,
        env: const Env(),
        logger: Logger.detached('InvitePanelTags'),
      );
      final directory = ConstellationFieldSearchRepository(remote);
      final search = ConstellationFieldSearchCase(directory);
      final store = ConstellationFieldStoreCase(
        ConstellationRepository(remote),
        _Account(),
        clock,
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env(),
        logger: Logger.detached('InvitePanelField'),
        phantomsEnabled: true,
      );
      final cubit = ConstellationCubit(
        case_: store,
        viewer: _viewer,
        loadOnCreate: false,
        fieldSearchCase: search,
      );
      final getIt = GetIt.I
        ..pushNewScope(
          init: (scope) {
            scope
              ..registerSingleton<ClockPort>(clock)
              ..registerSingleton<Logger>(
                Logger.detached('InvitePanelEffects'),
              )
              ..registerSingleton<AppNavigator>(FakeAppNavigator())
              ..registerSingleton<UiEffectPort>(effects)
              ..registerSingleton<PeopleTagsCase>(peopleTags)
              ..registerSingleton<ConstellationFieldStoreCase>(store)
              ..registerSingleton<ConstellationFieldSearchCase>(search)
              ..registerSingleton<PhantomRepositoryPort>(
                PhantomRepository(remote),
              );
          },
        );
      addTearDown(() async {
        await cubit.close();
        await store.dispose();
        await peopleTags.dispose();
        await realtime.port.dispose();
        await getIt.popScope();
      });
      await peopleTags.load().timeout(const Duration(seconds: 4));
      expect(
        peopleTags.tags.map((tag) => tag.name),
        unorderedEquals(_tags.values),
      );
      final directoryResult = await directory
          .search(
            query: _directoryPersonName,
            context: '',
          )
          .timeout(const Duration(seconds: 4));
      expect(directoryResult.people.single.id, _directoryPerson);
      await cubit.load().timeout(const Duration(seconds: 4));
      expect(cubit.state.loadError, isNull);
      expect(
        wire.sent.map((call) => call.operationName),
        contains('ConstellationFieldFetch'),
      );
      expect(
        cubit.state.field?.phantoms.map((entry) => entry.displayName),
        unorderedEquals([name, _otherEntryName]),
        reason: 'The transport response populated the real Field store',
      );
      expect(cubit.state.field?.peers.map((entry) => entry.id), [_fieldPerson]);

      final phone = locale.languageCode == 'ru';
      if (phone) await usePhoneSurface(tester);
      await pumpConstellationBody(
        tester,
        cubit,
        effects: effects,
        locale: locale,
        size: phone ? kPhoneSurface : const Size(1200, 900),
        disableAnimations: true,
        wrapBody: (child) => UiEffectHandler(
          effects: effects,
          child: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await body(wire);
    },
    responseFor: wire.respond,
    selectResponse: _selectPhantomFields,
    errors: {
      ?reject: {
        'message': 'Anna is joining right now.',
        // The V2 representation of GeneralExceptionCode.phantomJoining.
        'extensions': {'code': '1007', 'path': ''},
      },
    },
  );
}

class _PanelWire {
  _PanelWire({
    required this.name,
    required this.tagged,
    required bool live,
  }) : inviteCreatedAt = live ? _inviteCreatedAt : null;

  final String name;
  final bool tagged;
  DateTime? inviteCreatedAt;
  bool removed = false;
  String code = _originalCode;
  final sent = <WireSent>[];
  final clipboard = <String>[];

  List<Map<String, dynamic>> variablesFor(String operation) => [
    for (final call in sent)
      if (call.operationName == operation) call.variables,
  ];

  Future<Map<String, dynamic>> respond(WireSent call) async {
    switch (call.operationName) {
      case 'ConstellationFieldFetch':
      case 'ConstellationAnchorsFetch':
        return _snapshot();
      case 'PersonTags':
        return {
          'personTags': [
            for (final (index, tag) in _tags.entries.indexed)
              {
                '__typename': 'v2_PersonTag',
                'id': tag.key,
                'name': tag.value,
                'glyph': tag.value[0],
                'color': 2,
                'ord': index,
                'count': 0,
                'countOffField': 0,
              },
          ],
        };
      case 'PersonTagMemberships':
        return {'personTagMemberships': <Object?>[]};
      case 'PersonAutoTags':
        return {'personAutoTags': <Object?>[]};
      case 'FieldSearch':
        return {
          'fieldSearch': {
            '__typename': 'v2_FieldSearchResult',
            'people': [
              if (_directoryPersonName.toLowerCase().contains(
                (call.variables['query'] as String).toLowerCase(),
              ))
                {
                  '__typename': 'v2_FieldSearchPerson',
                  'id': _directoryPerson,
                  'displayName': _directoryPersonName,
                },
            ],
            'requests': <Object?>[],
            'posts': <Object?>[],
          },
        };
      case 'PhantomInviteEnsure':
        inviteCreatedAt ??= _now;
        return {'phantomInviteEnsure': code};
      case 'PhantomInviteRotate':
        code = _rotatedCode;
        inviteCreatedAt = _now;
        return {'phantomInviteRotate': code};
      case 'PhantomLink':
        removed = true;
        return {'phantomLink': true};
      case 'PhantomDelete':
        removed = true;
        return {'phantomDelete': true};
      default:
        throw StateError('Unexpected GraphQL operation ${call.operationName}');
    }
  }

  Map<String, dynamic> _snapshot() => {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': _now.toIso8601String(),
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': [_fieldPerson],
      'peers': [
        {
          '__typename': 'v2_ConstellationPeer',
          'id': _fieldPerson,
          'displayName': _fieldPersonName,
          'contactOnly': false,
          'presence': 'visible',
          'bondContexts': <Object?>[],
          'isNew': false,
        },
      ],
      'edges': [
        {
          '__typename': 'v2_ConstellationEdge',
          'src': _viewer.id,
          'dst': _fieldPerson,
          'tier': 1,
        },
      ],
      'requests': <Object?>[],
      'posts': <Object?>[],
      'memberWebs': <Object?>[],
      'phantoms': [
        if (!removed)
          {
            '__typename': 'v2_ConstellationPhantom',
            'id': _anna,
            'displayName': name,
            'hasPrivateAvatar': false,
            'ownTagIds': tagged ? _tags.keys.take(2).toList() : <String>[],
            'inviteState': inviteCreatedAt == null ? 'none' : 'live',
            'inviteCreatedAt': inviteCreatedAt?.toIso8601String(),
            'createdAt': _now
                .subtract(const Duration(days: 20))
                .toIso8601String(),
          },
        {
          '__typename': 'v2_ConstellationPhantom',
          'id': 'PH1234567890ab',
          'displayName': _otherEntryName,
          'hasPrivateAvatar': false,
          'ownTagIds': <String>[],
          'inviteState': 'none',
          'createdAt': _now.toIso8601String(),
        },
      ],
      'anchorProjection': {
        '__typename': 'v2_ConstellationAnchorProjection',
        'revision': '0',
        'anchors': <Object?>[],
        'pinnedPeers': <Object?>[],
        'pinnedRequests': <Object?>[],
        'supportPeers': <Object?>[],
        'supportEdges': <Object?>[],
        'serverFilteredBeaconIds': <String>[],
        'serverFilteredBeaconCount': 0,
      },
    },
  };
}

// Model the server's selection set so an unrequested timestamp cannot
// reach the mapper through permissive fixture JSON.
Map<String, dynamic> _selectPhantomFields(
  String query,
  Map<String, dynamic> data,
) {
  final snapshot = data['constellationField'];
  if (snapshot is! Map<String, dynamic>) return data;
  final operation = parseString(
    query,
  ).definitions.whereType<OperationDefinitionNode>().single;
  final field = operation.selectionSet.selections
      .whereType<FieldNode>()
      .singleWhere(
        (node) => node.name.value == 'constellationField',
      );
  final selectedFields = {
    for (final node in field.selectionSet!.selections.whereType<FieldNode>())
      if (node.name.value == 'phantoms')
        for (final selection
            in node.selectionSet!.selections.whereType<FieldNode>())
          selection.name.value,
  };
  return {
    ...data,
    'constellationField': {
      ...snapshot,
      'phantoms': [
        if (selectedFields.isNotEmpty)
          for (final row
              in (snapshot['phantoms'] as List<Map<String, dynamic>>))
            {
              '__typename': row['__typename'],
              for (final key in selectedFields) key: row[key],
            },
      ],
    },
  };
}
