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
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/adaptive_context_overlay.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../support/attention_case_factory.dart';
import '../../support/constellation_composer_screen_harness.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _privateId = 'PH0123456789ab';
const _privateName = 'Anna K.';
const _otherPrivateId = 'PH1234567890ab';
const _otherPrivateName = 'Mia R.';
const _memberId = 'Uanna00000001';
const _memberName = 'Anna Smith';
const _pickedId = 'Unora00000001';
const _pickedName = 'Nora Bell';
const _history = AttentionFeedDestinationId.history;
const _merge = 'phantomMerged';
const _joined = 'phantomJoined';
const _unmerge = {
  'operationName': 'PhantomUnmerge',
  'variables': {'phantomId': _privateId},
};

final _now = DateTime.utc(2026, 11, 25, 12);
final _internalWords = RegExp('phantom|фантом', caseSensitive: false);
final _russian = RegExp('[А-Яа-яЁё]');
final _letters = RegExp('[A-Za-zА-Яа-яЁё]');

void main() {
  group('Field actions for private people who join Tentura', () {
    for (final locale in ['en', 'ru']) {
      testWidgets(
        'the merge snackbar names the person and Undo unlinks once ($locale)',
        (
          tester,
        ) async {
          await _withScreen(tester, locale, (field, _) async {
            expect(_snack, findsNothing);
            await field.deliver(tester, _merge);
            final undo = _expectNamedUndo(tester, locale);
            expect(field.writes, isEmpty);
            await tester.tap(undo);
            await tester.pumpAndSettle();
            expect(field.writes, [_unmerge]);
            expect(tester.takeException(), isNull);
          });
        },
      );

      testWidgets(
        'the merged person panel offers Unlink to its owner ($locale)',
        (
          tester,
        ) async {
          await _withScreen(tester, locale, (field, cubit) async {
            await _openPanel(tester, 'fh:$_otherPrivateId', _otherPrivateName);
            final status = _catalog(locale)['constellationPhantomStatus']!;
            expect(
              status,
              locale == 'en' ? 'Not on Tentura yet' : 'Ещё не в Тентуре',
            );
            expect(_inPanel(_text(status)), findsOneWidget);
            expect(_inPanel(_unlink(locale)), findsNothing);
            final close = _catalog(locale)['buttonClose']!;
            await tester.tap(_inPanel(find.byTooltip(close)));
            await tester.pumpAndSettle();

            await _selectFieldPerson(tester, cubit, _pickedId, _pickedName);
            expect(_inPanel(_unlink(locale)), findsNothing);
            await _selectFieldPerson(tester, cubit, _memberId, _memberName);
            final action = _inPanel(_unlink(locale));
            expect(
              action,
              findsOneWidget,
              reason: 'The viewer owns the active merge for this account',
            );
            _expectCatalogCopy(locale, _visibleText(tester, action));
            _expectPublicWording(tester, _panel);
            expect(field.writes, isEmpty);
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(field.writes, [_unmerge]);
            expect(tester.takeException(), isNull);
          }, merged: true);
        },
      );

      testWidgets(
        'the joined card opens the Field picker for the invited person ($locale)',
        (
          tester,
        ) async {
          await _withScreen(tester, locale, (field, _) async {
            final headline = find.textContaining(
              locale == 'en'
                  ? RegExp(
                      r'Anna K\.[”"»]? joined Tentura\s*[—–-]\s*link\?',
                      caseSensitive: false,
                    )
                  : RegExp(r'Anna K\..*Тентур.*\?', caseSensitive: false),
              findRichText: true,
            );
            expect(headline, findsNothing);
            await field.deliver(tester, _joined);
            expect(headline, findsOneWidget);
            final headlineCopy = _visibleText(tester, headline);
            _expectCatalogCopy(locale, headlineCopy, name: _privateName);
            expect(field.writes, isEmpty);

            final action = _joinedCardAction(tester, headline);
            for (final label in _textWithin(tester, action)) {
              if (label != headlineCopy && _letters.hasMatch(label)) {
                _expectCatalogCopy(locale, label);
              }
            }
            await tester.tap(action);
            await tester.pumpAndSettle();
            final pickerTitle = _catalog(locale)['personPanelPickExisting']!;
            expect(_text(pickerTitle), findsOneWidget);
            expect(
              field.writes,
              isEmpty,
              reason: 'Opening the picker must not link the event recipient',
            );

            final otherPerson = find.descendant(
              of: find.byType(ListTile),
              matching: _text(_pickedName),
            );
            expect(otherPerson, findsOneWidget);
            await tester.tap(otherPerson);
            await tester.pumpAndSettle();
            expect(field.writes, [
              {
                'operationName': 'PhantomLink',
                'variables': {'phantomId': _privateId, 'userId': _pickedId},
              },
            ]);
            expect(tester.takeException(), isNull);
          });
        },
      );
    }

    testWidgets(
      'closing the merge snackbar keeps the link and replay never opens it again',
      (
        tester,
      ) async {
        await _withScreen(tester, 'en', (field, _) async {
          expect(_snack, findsNothing);
          await field.deliver(tester, _merge);
          _expectNamedUndo(tester, 'en');
          await field.deliver(tester, _merge);
          expect(_snack, findsOneWidget);

          ScaffoldMessenger.of(tester.element(_snack)).hideCurrentSnackBar();
          await tester.pumpAndSettle();
          expect(_snack, findsNothing);
          expect(field.writes, isEmpty);

          await field.deliver(tester, _merge);
          expect(_snack, findsNothing);
          expect(field.writes, isEmpty);
          expect(tester.takeException(), isNull);
        });
      },
    );
  });
}

Finder get _snack => find.byType(SnackBar);
Finder get _panel => find.byType(AdaptiveContextOverlay);
Finder _text(String copy) => find.text(copy, findRichText: true);
Finder _inPanel(Finder matching) =>
    find.descendant(of: _panel, matching: matching);
Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Finder _expectNamedUndo(WidgetTester tester, String locale) {
  expect(_snack, findsOneWidget);
  final message = find.descendant(
    of: _snack,
    matching: find.textContaining(_privateName, findRichText: true),
  );
  expect(message, findsOneWidget);
  _expectCatalogCopy(locale, _visibleText(tester, message), name: _privateName);
  final undo = find.descendant(
    of: _snack,
    matching: find.byType(SnackBarAction),
  );
  expect(undo, findsOneWidget);
  final label = tester.widget<SnackBarAction>(undo).label;
  expect(label.toLowerCase(), locale == 'en' ? 'undo' : 'отменить');
  _expectCatalogCopy(locale, label);
  _expectPublicWording(tester, _snack);
  return _text(label).hitTestable();
}

Future<void> _openPanel(WidgetTester tester, String id, String name) async {
  expect(_node(id), findsOneWidget);
  await tester.tap(_node(id));
  await tester.pumpAndSettle();
  expect(_inPanel(_text(name)), findsWidgets);
  expect(tester.takeException(), isNull);
}

Future<void> _selectFieldPerson(
  WidgetTester tester,
  ConstellationCubit cubit,
  String id,
  String name,
) async {
  // Open the same panel as a graph selection regardless of the phone camera.
  expect(_node(id), findsOneWidget);
  cubit.selectPerson(id);
  await tester.pumpAndSettle();
  expect(_inPanel(_text(name)), findsWidgets);
  expect(tester.takeException(), isNull);
}

Finder _unlink(String locale) {
  if (locale == 'en') {
    return find.textContaining(
      RegExp(r'^unlink$', caseSensitive: false),
      findRichText: true,
    );
  }
  final en = _catalog('en');
  final ru = _catalog('ru');
  final labels = {
    for (final key in en.keys)
      if (en[key]!.toLowerCase() == 'unlink' && ru.containsKey(key)) ru[key]!,
  };
  return find.textContaining(
    RegExp(
      labels.isEmpty
          ? r'(?!)'
          : '^(${labels.map(RegExp.escape).join('|')})'
                r'$',
      caseSensitive: false,
    ),
    findRichText: true,
  );
}

Finder _joinedCardAction(WidgetTester tester, Finder headline) {
  Finder? action;
  tester.element(headline).visitAncestorElements((element) {
    final widget = element.widget;
    final container = find.byWidget(widget);
    if ((widget is InkResponse && widget.onTap != null) ||
        (widget is GestureDetector && widget.onTap != null) ||
        (widget is ListTile && widget.onTap != null) ||
        (widget is ButtonStyleButton && widget.onPressed != null)) {
      action = container.hitTestable();
    } else {
      final buttons = find
          .descendant(
            of: container,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ButtonStyleButton && widget.onPressed != null,
            ),
          )
          .hitTestable();
      if (buttons.evaluate().length == 1) action = buttons;
    }
    return action == null;
  });
  expect(
    action,
    isNotNull,
    reason: 'The joined card opens a manual link picker',
  );
  expect(action!, findsOneWidget);
  return action!;
}

String _visibleText(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  return switch (widget) {
    Text() => widget.data ?? widget.textSpan!.toPlainText(),
    RichText() => widget.text.toPlainText(),
    _ => throw StateError('Expected a visible text label'),
  };
}

Iterable<String> _textWithin(WidgetTester tester, Finder parent) => tester
    .widgetList<RichText>(
      find.descendant(of: parent, matching: find.byType(RichText)),
    )
    .map((label) => label.text.toPlainText());

void _expectPublicWording(WidgetTester tester, Finder parent) {
  expect(_textWithin(tester, parent).join(' '), isNot(matches(_internalWords)));
}

Map<String, String> _catalog(String locale) {
  final entries =
      jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
          as Map<String, Object?>;
  return {
    for (final MapEntry(:key, :value) in entries.entries)
      if (!key.startsWith('@') && value is String) key: value,
  };
}

void _expectCatalogCopy(String locale, String shown, {String? name}) {
  final displayedLocale = _catalog(locale);
  final en = _catalog('en');
  final ru = _catalog('ru');
  final parameter = RegExp(r'\{\w+\}');
  final matchingKeys = displayedLocale.keys.where((key) {
    final template = displayedLocale[key]!;
    final rendered = name == null
        ? template
        : template.replaceAll(parameter, name);
    return rendered.toLowerCase() == shown.toLowerCase() &&
        (name == null ||
            (parameter.hasMatch(en[key] ?? '') &&
                parameter.hasMatch(ru[key] ?? '')));
  });
  expect(
    matchingKeys,
    isNotEmpty,
    reason: 'Displayed copy comes from its locale catalog',
  );
  expect(
    matchingKeys.where((key) {
      final english = en[key];
      final russian = ru[key];
      return english != null &&
          russian != null &&
          !_internalWords.hasMatch(english) &&
          !_internalWords.hasMatch(russian) &&
          _russian.hasMatch(russian);
    }),
    isNotEmpty,
    reason: 'The same key supplies English and Russian user-facing copy',
  );
  expect(shown, isNot(matches(_internalWords)));
}

class _Account implements AttentionAccountPort, ConstellationAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer.id);
}

Future<void> _withScreen(
  WidgetTester tester,
  String locale,
  Future<void> Function(_OwnerWire field, ConstellationCubit cubit) exercise, {
  bool merged = false,
}) async {
  final wire = _OwnerWire(merged: merged);
  final size = locale == 'ru' ? kPhoneSurface : const Size(1200, 900);
  if (locale == 'ru') {
    await usePhoneSurface(tester);
  } else {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await withRemoteWire(
    {},
    wire.sent,
    (remote) async {
      final realtime = buildTestRealtimeSync();
      final attentionRepository = AttentionRepository(remote);
      final attention = buildAttentionCase(
        repository: attentionRepository,
        accounts: _Account(),
        realtimeSyncCase: realtime.case_,
      );
      wire
        ..attention = attention
        ..realtime = realtime.port;
      final store = ConstellationFieldStoreCase(
        ConstellationRepository(remote),
        _Account(),
        FakeClockPort(_now),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env(),
        logger: Logger.detached('OwnerLinkFieldTest'),
        phantomsEnabled: true,
      );
      final cubit = ConstellationCubit(
        case_: store,
        viewer: _viewer,
        loadOnCreate: false,
      );
      final effects = FakeUiEffectPort();
      final getIt = GetIt.I
        ..pushNewScope(
          init: (scope) {
            scope
              ..registerSingleton<AttentionCase>(attention)
              ..registerSingleton<AttentionRepositoryPort>(attentionRepository)
              ..registerSingleton<PhantomRepositoryPort>(
                PhantomRepository(remote),
              );
          },
        );
      addTearDown(() async {
        await cubit.close();
        await store.dispose();
        await attention.dispose();
        await realtime.port.dispose();
        await getIt.popScope();
      });

      await cubit.load().timeout(const Duration(seconds: 4));
      expect(cubit.state.loadError, isNull);
      expect(
        wire.sent.map((call) => call.operationName),
        contains('ConstellationFieldFetch'),
      );
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: Locale(locale),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          scaffoldMessengerKey: snackbarKey,
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ConstellationCubit>.value(value: cubit),
                  BlocProvider(create: (_) => ConstellationSelectionCubit()),
                  BlocProvider(create: (_) => HomeTabReselectCubit()),
                  BlocProvider<GraphPersonContextCubit>(
                    create: (_) => ComposerHarnessContextCubit(),
                  ),
                  BlocProvider(create: (_) => ScreenCubit(effects)),
                ],
                child: UiEffectHandler(
                  effects: effects,
                  child: const ConstellationScreen(),
                ),
              ),
            ),
          ),
        ),
      );
      try {
        attention.attachFeedSession(_history);
        await tester.pumpAndSettle();
        expect(find.byType(ConstellationScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await exercise(wire, cubit);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    responseFor: wire.respond,
    selectResponse: _selectMergeFact,
  );
}

Map<String, dynamic> _selectMergeFact(String query, Map<String, dynamic> data) {
  final field = data['constellationField'];
  if (field is! Map<String, dynamic>) return data;
  final operation = parseString(
    query,
  ).definitions.whereType<OperationDefinitionNode>().single;
  final snapshot = operation.selectionSet.selections
      .whereType<FieldNode>()
      .singleWhere((node) => node.name.value == 'constellationField');
  final asksForMerge = snapshot.selectionSet!.selections
      .whereType<FieldNode>()
      .where((node) => node.name.value == 'peers')
      .any(
        (node) => node.selectionSet!.selections.whereType<FieldNode>().any(
          (peer) => peer.name.value == 'mergedPhantomId',
        ),
      );
  if (asksForMerge) return data;
  return {
    ...data,
    'constellationField': {
      ...field,
      'peers': [
        for (final peer in field['peers'] as List<Map<String, dynamic>>)
          {...peer}..remove('mergedPhantomId'),
      ],
    },
  };
}

class _OwnerWire {
  _OwnerWire({required bool merged}) : mergedUserId = merged ? _memberId : null;

  late final AttentionCase attention;
  late final TestRealtimeSyncPort realtime;
  final sent = <WireSent>[];
  String? mergedUserId;
  String? eventType;

  List<Map<String, Object?>> get writes => [
    for (final call in sent)
      if (call.operationName.startsWith('Phantom'))
        {'operationName': call.operationName, 'variables': call.variables},
  ];

  Future<void> deliver(WidgetTester tester, String event) async {
    if (event == _merge && eventType != event) mergedUserId = _memberId;
    eventType = event;
    final previousReads = sent
        .where((call) => call.operationName == 'AttentionFeed')
        .length;
    final key = _sourceKey(event);
    final previousPage = attention.feedSession(_history);
    realtime.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.notification,
        aggregateId: 'Uviewer000001',
        operation: RealtimeOperation.insert,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    var session = attention.feedSession(_history);
    for (
      var frame = 0;
      frame < 20 && identical(session, previousPage);
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
      session = attention.feedSession(_history);
    }
    expect(
      sent.where((call) => call.operationName == 'AttentionFeed').length,
      greaterThan(previousReads),
    );
    expect(
      session,
      isNot(same(previousPage)),
      reason: 'The event reached the live feed',
    );
    expect(session.headRefreshError, isNull);
    final rows = session.pages[AttentionView.all]!.items;
    expect(
      rows.singleWhere((row) => row.sourceEventKey == key).targetEntityId,
      _privateId,
    );
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> respond(WireSent call) async {
    switch (call.operationName) {
      case 'AttentionSurfaceSummary':
        return {
          'attentionSurfaceSummary': {
            '__typename': 'v2_AttentionSurfaceSummary',
            'unreadTotal': 0,
            'needsYouTotal': 0,
            'myDeskDot': false,
            'myDeskCount': 0,
            'forYouDot': false,
            'forYouSweepEligible': false,
            'forYouReceiptSweepEligible': false,
          },
        };
      case 'AttentionFeed':
        final event = eventType;
        return {
          'attentionFeed': {
            '__typename': 'v2_AttentionFeed',
            'summary': {
              '__typename': 'v2_AttentionSummary',
              'unreadTotal': event == null ? 0 : 1,
              'needsYouTotal': 0,
            },
            'page': {
              '__typename': 'v2_AttentionPage',
              'items': [if (event != null) _eventRow(event)],
            },
          },
        };
      case 'AttentionMarkSeen':
        return {'attentionMarkSeen': 1};
      case 'ConstellationFieldFetch':
      case 'ConstellationAnchorsFetch':
        return _field();
      case 'PhantomUnmerge':
        if (call.variables['phantomId'] == _privateId) mergedUserId = null;
        return {'phantomUnmerge': true};
      case 'PhantomLink':
        if (call.variables['phantomId'] == _privateId) {
          mergedUserId = call.variables['userId'] as String;
        }
        return {'phantomLink': true};
      default:
        throw StateError('Unexpected GraphQL operation ${call.operationName}');
    }
  }

  String _sourceKey(String event) =>
      event == _merge ? '$_merge:PM0123456789' : '$_joined:PJ0123456789';

  // Proposed in-app projection of the persisted owner occurrence. The feed
  // operation and receipt envelope already exist. The event-specific payload
  // keeps the source event key and ids recorded by the merge repository.
  Map<String, dynamic> _eventRow(String event) => {
    '__typename': 'v2_AttentionReceipt',
    'id': event == _merge ? 'Nmerge0000001' : 'Njoined000001',
    'sourceEventKey': _sourceKey(event),
    'kind': event,
    'category': 'system',
    'priority': 'normal',
    'title': '',
    'body': '',
    'actionUrl': '',
    'createdAt': _now.toIso8601String(),
    'collapsedCount': 1,
    'actorUserId': _viewer.id,
    'targetEntityId': _privateId,
    'presentationPayloadJson': jsonEncode({
      'eventType': event,
      'targetEntityId': _privateId,
      if (event == _merge) 'mergeId': 'PM0123456789' else 'userId': _memberId,
    }),
    'requiresAction': false,
    'surface': 'activity',
    'itemKind': 'receipt',
    'eventsPreview': <Object?>[],
  };

  Map<String, dynamic> _field() => {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'context': '',
      'loadedAt': _now.toIso8601String(),
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': [_memberId, _pickedId],
      'peers': [
        for (final (id, name) in [
          (_memberId, _memberName),
          (_pickedId, _pickedName),
        ])
          _peer(
            id,
            name,
            mergedPhantomId: mergedUserId == id ? _privateId : null,
          ),
      ],
      'edges': [
        for (final id in [_memberId, _pickedId])
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
      'linkHints': <Object?>[],
      'phantoms': [
        if (mergedUserId == null) _privatePerson(_privateId, _privateName),
        _privatePerson(_otherPrivateId, _otherPrivateName),
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

  Map<String, dynamic> _peer(
    String id,
    String name, {
    String? mergedPhantomId,
  }) => {
    '__typename': 'v2_ConstellationPeer',
    'id': id,
    'displayName': name,
    'contactOnly': false,
    'presence': 'visible',
    'bondContexts': <Object?>[],
    'isNew': false,
    // Proposed nullable owner-only read fact for a person's current merge.
    'mergedPhantomId': mergedPhantomId,
  };

  Map<String, dynamic> _privatePerson(String id, String name) => {
    '__typename': 'v2_ConstellationPhantom',
    'id': id,
    'displayName': name,
    'hasPrivateAvatar': false,
    'ownTagIds': <String>[],
    'inviteState': 'none',
    'createdAt': _now.subtract(const Duration(days: 20)).toIso8601String(),
  };
}
