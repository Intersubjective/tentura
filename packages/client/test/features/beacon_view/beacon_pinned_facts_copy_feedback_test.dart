import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fact_sheet_feedback.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fact_origin_test_support.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart' show pumpUntil;

const _requestId = 'Brequest0001';
const _sourceRequestId = 'Bsource00001';
const _destinationId = 'Bgarden00001';
const _sourceFactId = 'Fsource00001';
const _copiedFactId = 'Fcopied00001';
const _factText = 'Shed key';
const _query = 'Shed';
const _destination = 'Garden day';
const _author = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _desktopSurface = Size(1280, 800);
const _destinationNote = 'It will be visible in that discussion only.';
const _en = Locale('en');
const _ru = Locale('ru');

final _picker = find.byType(FactPickerSheet);
final _cards = find.byType(BeaconPinnedFactCard);

Finder _inPicker(Finder child) => find.descendant(of: _picker, matching: child);

enum _CopyOutcome {
  created('created'),
  alreadyThere('alreadyThere');

  const _CopyOutcome(this.wireValue);

  final String wireValue;
}

void main() {
  group('Picking a fact while Pinned facts is open', () {
    for (final (surface, locale, alreadyThere, added, origin) in [
      (
        kPhoneSurface,
        _en,
        'Already there',
        'Fact added',
        'Brought from another Request',
      ),
      (
        kPhoneSurface,
        _ru,
        'Уже там',
        'Факт добавлен',
        'Принесён из другого запроса',
      ),
      (
        _desktopSurface,
        _en,
        'Already there',
        'Fact added',
        'Brought from another Request',
      ),
    ]) {
      final layout = surface == kPhoneSurface ? 'phone' : 'desktop';
      final language = locale == _ru ? 'Russian' : 'English';

      testWidgets(
        'an existing copy from All my facts keeps four cards and shows feedback on $layout in $language',
        (tester) => _withPinnedFacts(
          tester,
          surface: surface,
          locale: locale,
          outcome: _CopyOutcome.alreadyThere,
          check: (l10n, sent, sheet) async {
            await _pickFact(tester, l10n, sent);
            await _expectReturnedToPinnedFacts(tester, l10n, sheet, count: 4);
            expect(_cardFor(sheet, _factText), findsOneWidget);
            _expectCopyTo(sent, _sourceFactId, _requestId);
            _expectFeedback(tester, surface, alreadyThere);
          },
        ),
      );

      testWidgets(
        'a new copy from All my facts adds a fifth card with its origin and shows feedback on $layout in $language',
        (tester) => _withPinnedFacts(
          tester,
          surface: surface,
          locale: locale,
          check: (l10n, sent, sheet) async {
            await _pickFact(tester, l10n, sent);
            await _expectReturnedToPinnedFacts(tester, l10n, sheet, count: 5);
            expect(
              find.descendant(
                of: _cardFor(sheet, _factText),
                matching: find.text(origin).hitTestable(),
              ),
              findsOneWidget,
            );
            _expectCopyTo(sent, _sourceFactId, _requestId);
            _expectFeedback(tester, surface, added);
          },
        ),
      );
    }

    for (final (locale, language, pickerTitle, pinnedTitle, message) in [
      (_en, 'English', 'Pick a fact', 'Pinned facts', 'Fact added'),
      (_ru, 'Russian', 'Выберите факт', 'Закреплённые факты', 'Факт добавлен'),
    ]) {
      testWidgets(
        'Escape closes only the focused picker and reopening Saved shows copy feedback on a phone in $language',
        (tester) => _withPinnedFacts(
          tester,
          locale: locale,
          check: (l10n, sent, sheet) async {
            await _openPicker(tester, l10n);
            expect(_inPicker(find.text(pickerTitle)), findsOneWidget);
            await tester.tap(_inPicker(find.byType(TextField)).hitTestable());
            await tester.pump();
            final editor = tester.widget<EditableText>(
              _inPicker(find.byType(EditableText)),
            );
            expect(editor.focusNode.hasFocus, isTrue);

            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await pumpRealAsync(tester);

            expect(
              find.byType(FactPickerSheet, skipOffstage: false),
              findsNothing,
            );
            expect(find.text(pickerTitle, skipOffstage: false), findsNothing);
            final pinnedHeading = find.text(pinnedTitle, skipOffstage: false);
            expect(pinnedHeading, findsOneWidget);
            expect(pinnedHeading.hitTestable(), findsOneWidget);
            await _expectReturnedToPinnedFacts(tester, l10n, sheet, count: 4);

            await _pickFact(tester, l10n, sent, fromSaved: true);
            await _expectReturnedToPinnedFacts(tester, l10n, sheet, count: 5);
            expect(_cardFor(sheet, _factText), findsOneWidget);
            _expectCopyTo(sent, _sourceFactId, _requestId);
            expectPhoneFeedback(tester, message);
          },
        ),
      );
    }
  });

  group('Copying a pinned fact to another Request on a phone', () {
    for (final (outcome, message) in [
      (_CopyOutcome.created, 'Copied to Garden day'),
      (_CopyOutcome.alreadyThere, 'Already there'),
    ]) {
      testWidgets(
        'closes the destination picker and shows $message above Pinned facts',
        (tester) => _withPinnedFacts(
          tester,
          outcome: outcome,
          check: (l10n, sent, sheet) async {
            await tester.longPress(
              _cardFor(sheet, 'Pinned note 1').hitTestable(),
            );
            await tester.pumpAndSettle();
            await _tapText(tester, 'Use in another Request or Post');
            await pumpRealAsync(tester);
            expect(find.text(_destinationNote), findsOneWidget);
            await _tapText(tester, _destination);
            await pumpRealAsync(tester);
            expect(find.text(_destinationNote), findsNothing);
            expect(find.text(_destination), findsNothing);
            await _expectReturnedToPinnedFacts(tester, l10n, sheet, count: 4);
            _expectCopyTo(sent, 'Fpinned00001', _destinationId);

            expectPhoneFeedback(tester, message);
            if (outcome == _CopyOutcome.created) {
              expect(
                find.widgetWithText(SnackBarAction, 'Open').hitTestable(),
                findsOneWidget,
              );
            }
          },
        ),
      );
    }
  });
}

Finder _pinnedSheet(ModalRoute<dynamic> route) => find.byElementPredicate(
  (element) => identical(element, route.subtreeContext),
  description: 'the original Pinned facts sheet route',
  skipOffstage: false,
);

Finder _inPinnedSheet(ModalRoute<dynamic> route, Finder child) =>
    find.descendant(of: _pinnedSheet(route), matching: child);

Finder _cardFor(ModalRoute<dynamic> sheet, String text) => find.ancestor(
  of: _inPinnedSheet(sheet, find.text(text, findRichText: true)),
  matching: _cards,
);

Future<void> _tapText(WidgetTester tester, String label) async {
  final control = find.text(label, findRichText: true).hitTestable();
  expect(control, findsOneWidget);
  await tester.tap(control);
}

Future<void> _openPicker(WidgetTester tester, L10n l10n) async {
  await _tapText(tester, l10n.beaconFactsAddFact);
  await tester.pumpAndSettle();
  await _tapText(tester, l10n.beaconFactsAddMenuPick);
  await pumpRealAsync(tester);
  expect(_picker, findsOneWidget);
}

Future<void> _pickFact(
  WidgetTester tester,
  L10n l10n,
  List<WireSent> sent, {
  bool fromSaved = false,
}) async {
  await _openPicker(tester, l10n);
  final fact = _inPicker(find.text(_factText, findRichText: true));
  if (fromSaved) {
    expect(
      _inPicker(find.text(l10n.beaconRoomFactPickerTabSaved)),
      findsOneWidget,
    );
  } else {
    final allFactsLabel = l10n.localeName == 'ru'
        ? 'Все мои факты'
        : 'All my facts';
    final allFactsTab = _inPicker(find.text(allFactsLabel)).hitTestable();
    expect(allFactsTab, findsOneWidget);
    await tester.tap(allFactsTab);
    await tester.pumpAndSettle();
    expect(fact, findsNothing, reason: 'this scope waits for a search');
    await tester.enterText(_inPicker(find.byType(TextField)), _query);
    await pumpRealAsync(tester);
    expect(
      sent
          .where((r) => r.operationName == 'BeaconFactCardSearch')
          .map((r) => r.variables),
      [
        {'query': _query, 'excludeBeaconId': _requestId},
      ],
      reason: 'the All my facts scope searches other Requests on the server',
    );
  }
  final result = fact.hitTestable();
  expect(result, findsOneWidget);
  await tester.tap(result);
  await pumpRealAsync(tester);
}

Future<void> _expectReturnedToPinnedFacts(
  WidgetTester tester,
  L10n l10n,
  ModalRoute<dynamic> sheet, {
  required int count,
}) async {
  expect(find.byType(FactPickerSheet, skipOffstage: false), findsNothing);
  expect(sheet.isActive, isTrue);
  expect(sheet.isCurrent, isTrue);
  expect(_pinnedSheet(sheet), findsOneWidget);
  final heading = find.text(l10n.beaconFactsSheetTitle, skipOffstage: false);
  expect(heading, findsOneWidget);
  expect(_inPinnedSheet(sheet, heading).hitTestable(), findsOneWidget);

  final scrollable = _inPinnedSheet(sheet, find.byType(Scrollable));
  final position = tester.state<ScrollableState>(scrollable).position;
  final start = position.pixels;
  final cards = _inPinnedSheet(sheet, _cards);
  // Scroll far enough to build the cards below the fold. Each step moves
  // less than one viewport, so the scan cannot skip over a card.
  final renderedCards = cards.evaluate().toSet();
  for (var step = 0; step < 12 && position.extentAfter > 0; step++) {
    await tester.drag(scrollable, Offset(0, -position.viewportDimension / 2));
    await tester.pumpAndSettle();
    renderedCards.addAll(cards.evaluate());
  }
  expect(position.extentAfter, 0, reason: 'visited the whole pinned list');
  expect(renderedCards, hasLength(count), reason: 'rendered pinned cards');
  if (position.pixels != start) {
    position.jumpTo(start);
    await tester.pumpAndSettle();
  }
}

void _expectCopyTo(List<WireSent> sent, String source, String destination) {
  expect(
    sent
        .where((r) => r.operationName == 'BeaconFactCardCopy')
        .map(
          (r) => r.variables,
        ),
    [
      {'sourceFactCardId': source, 'destinationBeaconId': destination},
    ],
  );
}

void _expectFeedback(WidgetTester tester, Size surface, String message) {
  if (surface == kPhoneSurface) {
    expectPhoneFeedback(tester, message);
  } else {
    expect(
      find.text(message, findRichText: true).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }
}

Future<void> _withPinnedFacts(
  WidgetTester tester, {
  required Future<void> Function(
    L10n l10n,
    List<WireSent> sent,
    ModalRoute<dynamic> sheet,
  )
  check,
  Size surface = kPhoneSurface,
  Locale locale = _en,
  _CopyOutcome outcome = _CopyOutcome.created,
}) async {
  registerPhoneFeedbackLogger();
  final sent = <WireSent>[];
  var broughtHere = false;
  await withRemoteWire(
    const {},
    sent,
    (remote) async {
      final repository = BeaconFactCardRepository(remote);
      registerFactRepository(repository);
      final cubit = (await tester.runAsync(() async {
        final now = DateTime.utc(2026);
        final cubit = BeaconViewCubit(
          id: _requestId,
          myProfile: _author,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: TrackingBeaconRepository()
              ..fetchByIdHandler = (_) async => Beacon(
                id: _requestId,
                title: 'Tool shed',
                author: _author,
                createdAt: now,
                updatedAt: now,
              ),
            factCardsRepo: _WireFactList(repository),
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
        return cubit;
      }))!;

      if (surface == kPhoneSurface) {
        await usePhoneSurface(tester);
      } else {
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: locale,
          // The Request workspace is nested. Pinned facts opens here, while
          // the fact picker and its destination sheet open on the root.
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => TenturaResponsiveScope(
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => unawaited(
                        showBeaconPinnedFactsSheet(context, cubit: cubit),
                      ),
                      child: const Text('Open pinned facts'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final l10n = lookupL10n(locale);
      await _tapText(tester, 'Open pinned facts');
      await tester.pumpAndSettle();
      final heading = find.text(l10n.beaconFactsSheetTitle);
      final sheet = ModalRoute.of(tester.element(heading))!;
      await _expectReturnedToPinnedFacts(tester, l10n, sheet, count: 4);
      await check(l10n, sent, sheet);
    },
    responseFor: (request) async {
      switch (request.operationName) {
        case 'BeaconFactCardList':
          final existingCopy = outcome == _CopyOutcome.alreadyThere;
          return {
            '__typename': 'query_root',
            'BeaconFactCardList': [
              for (var i = 1; i <= (existingCopy ? 3 : 4); i++)
                _factRow('Fpinned0000$i', 'Pinned note $i'),
              if (existingCopy || broughtHere)
                _factRow(_copiedFactId, _factText, fromAnotherRequest: true),
            ],
          };
        case 'BeaconFactCardSavedList':
          return {
            '__typename': 'query_root',
            'BeaconFactCardSavedList': [
              {
                '__typename': 'v2_BeaconFactCardSavedRow',
                ..._sourceFact,
                'available': true,
              },
            ],
          };
        case 'BeaconFactCardSearch':
          return {
            '__typename': 'query_root',
            'BeaconFactCardSearch': [
              {
                '__typename': 'v2_BeaconFactCardSearchRow',
                ..._sourceFact,
                'saved': true,
              },
            ],
          };
        case 'BeaconFactCopyDestinations':
          return {
            '__typename': 'query_root',
            'BeaconFactCopyDestinations': [
              {
                '__typename': 'v2_BeaconFactCopyDestinationRow',
                'id': _destinationId,
                'kind': 0,
                'title': _destination,
                'isDraft': false,
                'expiresAt': null,
              },
            ],
          };
        case 'BeaconFactCardCopy':
          broughtHere =
              outcome == _CopyOutcome.created &&
              request.variables['destinationBeaconId'] == _requestId;
          return {
            '__typename': 'mutation_root',
            'BeaconFactCardCopy': {
              '__typename': 'v2_BeaconFactCardCopyResult',
              'factCardId': _copiedFactId,
              'outcome': outcome.wireValue,
            },
          };
        default:
          throw StateError(
            'Unexpected GraphQL operation: ${request.operationName}',
          );
      }
    },
  );
}

const _sourceFact = {
  'factCardId': _sourceFactId,
  'beaconId': _sourceRequestId,
  'beaconKind': 0,
  'factText': _factText,
  'attachmentsJson': '[]',
};

Map<String, Object?> _factRow(
  String id,
  String text, {
  bool fromAnotherRequest = false,
}) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': id,
  'beaconId': _requestId,
  'factText': text,
  'visibility': BeaconFactCardVisibilityBits.public,
  'pinnedBy': _author.id,
  'pinnedByTitle': _author.displayName,
  'sourceMessageId': null,
  'status': BeaconFactCardStatusBits.active,
  'createdAt': fromAnotherRequest
      ? '2026-01-02T00:00:00Z'
      : '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'attachmentsJson': '[]',
  'revisionSeq': 1,
  'lastEditedBy': null,
  'lastEditedByTitle': null,
  'lastEditedAt': null,
  'otherEditorCount': 0,
  'historyTruncated': false,
  'originBeaconKind': fromAnotherRequest ? 0 : null,
  'savedByMe': false,
};

class _WireFactList extends FakeBeaconViewFactCardRepository {
  _WireFactList(this.repository);

  final BeaconFactCardRepository repository;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) =>
      repository.list(beaconId: beaconId);
}
