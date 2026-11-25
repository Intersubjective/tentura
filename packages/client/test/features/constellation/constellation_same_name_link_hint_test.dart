@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/ui/widget/adaptive_context_overlay.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _privateId = 'PH0123456789ab';
const _fieldId = 'Ufield0000001';
const _privateName = 'Anna K.';
const _fieldName = 'Anna Smith';
const _otherPrivateId = 'PH1234567890ab';
const _otherFieldId = 'Ufield0000002';
const _link = 'Link them';
const _dismiss = 'Not her';
const _fieldRead = 'ConstellationFieldFetch';
const _linkMutation = 'PhantomLink';
const _dismissMutation = 'PhantomHintDismiss';
const _pair = {'phantomId': _privateId, 'userId': _fieldId};

final _now = DateTime.utc(2026, 11, 25, 12);
final _internalWording = RegExp('phantom|фантом', caseSensitive: false);
final _russianText = RegExp('[А-Яа-яЁё]');
final _prose = RegExp('[A-Za-zА-Яа-яЁё]');
final _nameParameter = RegExp(r'\{\s*(\w+)\s*\}');

void main() {
  group('Same-name suggestions on the Field', () {
    testWidgets('a snapshot offers to link only the pair it suggests', (
      tester,
    ) async {
      await _withField(tester, (cubit, wire) async {
        expect(_text(_link), findsNothing);
        expect(_text(_dismiss), findsNothing);
        // Both people are on the Field even when the server has no suggestion.
        await _expectPanelWithoutUnlink(tester, _fieldId, _fieldName);
        await _expectPanelWithoutUnlink(tester, 'fh:$_privateId', _privateName);
        final withoutHint = _visibleCopy(tester);

        wire.hasHint = true;
        await cubit.load().timeout(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(
          wire.sent.where((call) => call.operationName == _fieldRead),
          hasLength(2),
        );
        expect(cubit.state.loadError, isNull);
        _expectSuggestion(tester, withoutHint, link: _link, dismiss: _dismiss);
        expect(wire.writes, isEmpty);
      });
    });

    testWidgets('linking a suggestion links those two people once', (
      tester,
    ) async {
      await _withField(tester, (_, wire) async {
        expect(wire.writes, isEmpty);
        final action = _text(_link);
        expect(action, findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(wire.writes, [
          {'operationName': _linkMutation, 'variables': _pair},
        ]);
        expect(tester.takeException(), isNull);
      }, hasHint: true);
    });

    testWidgets(
      'dismissing a suggestion dismisses that pair once and hides it',
      (
        tester,
      ) async {
        await _withField(tester, (_, wire) async {
          expect(wire.writes, isEmpty);
          final action = _text(_dismiss);
          expect(action, findsOneWidget);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(wire.writes, [
            {'operationName': _dismissMutation, 'variables': _pair},
          ]);
          expect(_text(_link), findsNothing);
          expect(_text(_dismiss), findsNothing);
          expect(_node(_fieldId), findsOneWidget);
          expect(_node('fh:$_privateId'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }, hasHint: true);
      },
    );

    testWidgets('the suggestion and both actions fit on a phone in Russian', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _withField(tester, (cubit, wire) async {
        final withoutHint = _visibleCopy(tester);
        wire.hasHint = true;
        await cubit.load().timeout(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(cubit.state.loadError, isNull);

        final link = _russianLabel(_link);
        final dismiss = _russianLabel(_dismiss);
        _expectSuggestion(tester, withoutHint, link: link, dismiss: dismiss);
        final explanations = _addedCopy(tester, withoutHint).where((label) {
          final prose = label
              .replaceAll(_privateName, '')
              .replaceAll(_fieldName, '');
          return label != link && label != dismiss && _prose.hasMatch(prose);
        });
        expect(
          explanations,
          isNotEmpty,
          reason: 'The suggestion text itself is Russian',
        );
        _expectHintExplanationsInCatalogs(explanations);
        expect(_text(_link), findsNothing);
        expect(_text(_dismiss), findsNothing);
        expect(_text(link).hitTestable(), findsOneWidget);
        expect(_text(dismiss).hitTestable(), findsOneWidget);
      }, locale: const Locale('ru'));
    });
  });

  test('undo, unlink and the joined notice have English and Russian copy', () {
    final en = _catalog('en');
    final ru = _catalog('ru');
    final messages = {
      'Undo': RegExp(r'^undo$', caseSensitive: false),
      'Unlink': RegExp(r'^unlink$', caseSensitive: false),
      'joined notice': RegExp(
        r'\{\w+\}.*joined Tentura\b.*\blink\?',
        caseSensitive: false,
      ),
    };
    final localized = {
      for (final MapEntry(key: description, value: pattern) in messages.entries)
        description: en.entries.any((entry) {
          final english = entry.value;
          final russian = ru[entry.key];
          return english is String &&
              pattern.hasMatch(english) &&
              russian is String &&
              RegExp('[А-Яа-яЁё]').hasMatch(russian) &&
              !_internalWording.hasMatch(english) &&
              !_internalWording.hasMatch(russian);
        }),
    };
    expect(localized, {
      for (final description in messages.keys) description: true,
    });
  });
}

Finder _text(String text) => find.text(text, findRichText: true);

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Map<String, int> _visibleCopy(WidgetTester tester) {
  final counts = <String, int>{};
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final text = richText.text.toPlainText();
    counts.update(text, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

Iterable<String> _addedCopy(WidgetTester tester, Map<String, int> before) =>
    _visibleCopy(tester).entries
        .where((entry) => entry.value > (before[entry.key] ?? 0))
        .map((entry) => entry.key);

void _expectSuggestion(
  WidgetTester tester,
  Map<String, int> withoutHint, {
  required String link,
  required String dismiss,
}) {
  expect(_text(link), findsOneWidget);
  expect(_text(dismiss), findsOneWidget);
  final newCopy = _addedCopy(tester, withoutHint).join('\n');
  expect(newCopy, allOf(contains(_privateName), contains(_fieldName)));
  expect(newCopy, isNot(matches(_internalWording)));
  expect(tester.takeException(), isNull);
}

Future<void> _expectPanelWithoutUnlink(
  WidgetTester tester,
  String id,
  String name,
) async {
  await tester.tap(_node(id));
  await tester.pumpAndSettle();
  final panel = find.byType(AdaptiveContextOverlay);
  expect(find.descendant(of: panel, matching: _text(name)), findsWidgets);
  expect(find.descendant(of: panel, matching: _text('Unlink')), findsNothing);
  await tester.tap(
    find.descendant(of: panel, matching: find.byTooltip('Close')),
  );
  await tester.pumpAndSettle();
  expect(panel, findsNothing);
}

Map<String, Object?> _catalog(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

String _russianLabel(String english) {
  final ru = _catalog('ru');
  final translated = {
    for (final entry in _catalog('en').entries)
      if (entry.value == english)
        if (ru[entry.key] case final String translation) translation,
  };
  expect(translated, hasLength(1), reason: '$english has an EN and RU entry');
  expect(translated.single, matches(_russianText));
  return translated.single;
}

void _expectHintExplanationsInCatalogs(Iterable<String> explanations) {
  final en = _catalog('en');
  final ru = _catalog('ru');
  for (final shown in explanations) {
    expect(shown, matches(_russianText));
    final paired = ru.entries.any((entry) {
      final russian = entry.value;
      final english = en[entry.key];
      if (entry.key.startsWith('@') ||
          russian is! String ||
          english is! String ||
          english.trim().isEmpty ||
          _internalWording.hasMatch(english)) {
        return false;
      }
      final parameters = _parametersOf(russian);
      final englishParameters = _parametersOf(english);
      if (parameters.length > 2 ||
          parameters.length != englishParameters.length ||
          !englishParameters.containsAll(parameters)) {
        return false;
      }

      // A translator can put either person's name first.
      for (final names in const [
        [_privateName, _fieldName],
        [_fieldName, _privateName],
      ]) {
        final arguments = Map.fromIterables(
          parameters,
          names.take(parameters.length),
        );
        final rendered = russian.replaceAllMapped(
          _nameParameter,
          (match) => arguments[match[1]]!,
        );
        if (rendered == shown) return true;
      }
      return false;
    });
    expect(
      paired,
      isTrue,
      reason: 'Visible hint text must use a shared EN/RU ARB key: $shown',
    );
  }
}

Set<String> _parametersOf(String template) => {
  for (final match in _nameParameter.allMatches(template)) match[1]!,
};

class _Account implements ConstellationAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer.id);
}

Future<void> _withField(
  WidgetTester tester,
  Future<void> Function(ConstellationCubit cubit, _FieldWire wire) body, {
  bool hasHint = false,
  Locale locale = const Locale('en'),
}) async {
  final wire = _FieldWire(hasHint: hasHint);
  await withRemoteWire(
    {},
    wire.sent,
    (remote) async {
      final realtime = buildTestRealtimeSync();
      final store = ConstellationFieldStoreCase(
        ConstellationRepository(remote),
        _Account(),
        FakeClockPort(_now),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env(),
        logger: Logger.detached('SameNameFieldTest'),
        phantomsEnabled: true,
      );
      final cubit = ConstellationCubit(
        case_: store,
        viewer: _viewer,
        loadOnCreate: false,
      );
      final getIt = GetIt.I
        ..pushNewScope(
          init: (scope) => scope.registerSingleton<PhantomRepositoryPort>(
            PhantomRepository(remote),
          ),
        );
      addTearDown(() async {
        await cubit.close();
        await store.dispose();
        await realtime.port.dispose();
        await getIt.popScope();
      });
      await cubit.load().timeout(const Duration(seconds: 4));
      expect(cubit.state.loadError, isNull);
      expect(wire.sent.first.operationName, _fieldRead);

      await pumpConstellationBody(
        tester,
        cubit,
        size: locale.languageCode == 'ru'
            ? kPhoneSurface
            : const Size(1200, 900),
        locale: locale,
        disableAnimations: true,
        wrapBody: (child) => Scaffold(body: child),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_node(_fieldId), findsOneWidget);
      expect(_node('fh:$_privateId'), findsOneWidget);
      await body(cubit, wire);
    },
    responseFor: wire.respond,
    selectResponse: _selectedHintFields,
  );
}

Map<String, dynamic> _selectedHintFields(
  String query,
  Map<String, dynamic> data,
) {
  final field = data['constellationField'];
  if (field is! Map<String, dynamic>) return data;
  final operation = parseString(
    query,
  ).definitions.whereType<OperationDefinitionNode>().single;
  final selection = operation.selectionSet.selections
      .whereType<FieldNode>()
      .singleWhere((node) => node.name.value == 'constellationField');
  final hints = selection.selectionSet!.selections.whereType<FieldNode>().where(
    (node) => node.name.value == 'linkHints',
  );
  // On the wire a GraphQL response omits unrequested fields.
  if (hints.isEmpty) {
    return {
      ...data,
      'constellationField': {...field}..remove('linkHints'),
    };
  }
  final selected = hints.single.selectionSet!.selections
      .whereType<FieldNode>()
      .map((node) => node.name.value)
      .toSet();
  final pairs = field['linkHints'] as List<Map<String, dynamic>>;
  return {
    ...data,
    'constellationField': {
      ...field,
      'linkHints': [
        for (final pair in pairs)
          {
            if (pair.containsKey('__typename'))
              '__typename': pair['__typename'],
            for (final key in selected)
              if (pair.containsKey(key)) key: pair[key],
          },
      ],
    },
  };
}

class _FieldWire {
  _FieldWire({required this.hasHint});

  bool hasHint;
  final sent = <WireSent>[];

  List<Map<String, Object?>> get writes => [
    for (final call in sent)
      if (call.operationName.startsWith('Phantom'))
        {'operationName': call.operationName, 'variables': call.variables},
  ];

  Future<Map<String, dynamic>> respond(WireSent call) async {
    switch (call.operationName) {
      case _fieldRead:
      case 'ConstellationAnchorsFetch':
        return _snapshot();
      case _linkMutation:
        return {'phantomLink': true};
      case _dismissMutation:
        if (call.variables['phantomId'] == _privateId &&
            call.variables['userId'] == _fieldId) {
          hasHint = false;
        }
        return {'phantomHintDismiss': true};
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
      'directContactIds': [_otherFieldId, _fieldId],
      'peers': [
        for (final (id, name) in [
          (_otherFieldId, 'Anna Ortiz'),
          (_fieldId, _fieldName),
        ])
          {
            '__typename': 'v2_ConstellationPeer',
            'id': id,
            'displayName': name,
            'contactOnly': false,
            'presence': 'visible',
            'bondContexts': <Object?>[],
            'isNew': false,
          },
      ],
      'edges': [
        for (final id in [_otherFieldId, _fieldId])
          {
            '__typename': 'v2_ConstellationEdge',
            'src': _viewer.id,
            'dst': id,
            'tier': 1,
          },
      ],
      'requests': <Object?>[],
      'posts': <Object?>[],
      'memberWebs': <Object?>[],
      'phantoms': [
        for (final (id, name) in [
          (_otherPrivateId, 'Anna T.'),
          (_privateId, _privateName),
        ])
          {
            '__typename': 'v2_ConstellationPhantom',
            'id': id,
            'displayName': name,
            'hasPrivateAvatar': false,
            'ownTagIds': <String>[],
            'inviteState': 'none',
            'createdAt': _now
                .subtract(const Duration(days: 20))
                .toIso8601String(),
          },
      ],
      'linkHints': <Map<String, dynamic>>[
        if (hasHint) {'__typename': 'v2_ConstellationLinkHint', ..._pair},
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
