@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_field_search_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_search_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_person_search.dart';
import 'package:tentura/features/phantoms/data/repository/person_note_repository.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _annaId = 'Uanna00000001';
const _kolyaId = 'PH0123456789ab';
const _offFieldUser = 'Uother0000001';
const _offFieldAccountless = 'PH111111111111';
const _query = 'plumber';

final _searchButton = find.byKey(const Key('constellation.app_bar.search'));
final _empty = find.byKey(const Key('constellation.field_search.empty'));
final _annaRow = _personRow(_annaId);
final _kolyaRow = _accountlessRow(_kolyaId);

void main() {
  for (final (locale, accountlessStatus) in const [
    (Locale('en'), 'Not on Tentura yet'),
    (Locale('ru'), 'Ещё не в Тентуре'),
  ]) {
    testWidgets(
      'a note match lists Anna under the localized People header and centres her on the Field in ${locale.languageCode}',
      (tester) async {
        final copy = _SearchCopy(locale);
        final wire = _SearchWire(userHits: [_annaId]);
        await _withField(tester, wire, (cubit) async {
          await _search(tester, _query, copy: copy);
          wire.expectNameSearch(_query);
          expect(_annaRow, findsOneWidget, reason: 'Anna matches only by note');
          expect(_inRow(_annaRow, 'Anna'), findsOneWidget);
          final header = find.text(
            copy['constellationFieldSearchPeople'].toUpperCase(),
          );
          expect(header, findsOneWidget);
          expect(
            tester.getTopLeft(header).dy,
            lessThan(tester.getTopLeft(_annaRow).dy),
          );
          copy.expectRendered(tester, names: const {'Anna'});
          wire.expectNoteSearch(_query);

          await _pick(
            tester,
            cubit,
            _annaRow,
            graphId: 'fp:$_annaId',
            person: true,
          );
          expect(cubit.state.selectedPersonId, _annaId);
        }, locale: locale);
      },
    );

    testWidgets(
      'a note match finds and focuses someone not on Tentura yet in ${locale.languageCode}',
      (tester) async {
        final copy = _SearchCopy(locale);
        final wire = _SearchWire(accountlessHits: [_kolyaId]);
        await _withField(tester, wire, (cubit) async {
          await _search(tester, _query, copy: copy);
          wire.expectNameSearch(_query);
          expect(
            _kolyaRow,
            findsOneWidget,
            reason: 'Kolya matches only by note',
          );
          expect(_inRow(_kolyaRow, 'Kolya'), findsOneWidget);
          expect(_inRow(_kolyaRow, accountlessStatus), findsOneWidget);
          copy.expectRendered(tester, names: const {'Kolya'});
          wire.expectNoteSearch(_query);

          await _pick(
            tester,
            cubit,
            _kolyaRow,
            graphId: 'fh:$_kolyaId',
            person: false,
          );
          expect(cubit.state.selectedPhantomId, _kolyaId);
        }, locale: locale);
      },
    );
    testWidgets(
      'note matches outside the loaded Field show the localized empty state in ${locale.languageCode}',
      (tester) async {
        final copy = _SearchCopy(locale);
        final wire = _SearchWire(
          userHits: [_offFieldUser],
          accountlessHits: [_offFieldAccountless],
        );
        await _withField(tester, wire, (cubit) async {
          expect(
            cubit.fieldPeople.map((person) => person.id),
            isNot(contains(_offFieldUser)),
          );
          expect(
            cubit.shownField!.phantoms.map((person) => person.id),
            isNot(contains(_offFieldAccountless)),
          );

          await _search(tester, _query, copy: copy);
          wire.expectNameSearch(_query);
          expect(
            _inRow(_empty, copy['constellationFieldSearchEmpty']),
            findsOneWidget,
          );
          expect(_personRow(_offFieldUser), findsNothing);
          expect(_accountlessRow(_offFieldAccountless), findsNothing);
          expect(find.text(_offFieldUser), findsNothing);
          expect(find.text(_offFieldAccountless), findsNothing);
          copy.expectRendered(tester, names: const {_query});
          // The empty state also occurs when private notes are never searched.
          wire.expectNoteSearch(_query);
        }, locale: locale);
      },
    );
  }

  testWidgets(
    'a note match for a loaded person excludes an off-Field accountless match',
    (
      tester,
    ) async {
      final wire = _SearchWire(
        userHits: [_annaId],
        accountlessHits: [_offFieldAccountless],
      );
      await _withField(tester, wire, (cubit) async {
        expect(
          cubit.shownField!.phantoms.map((person) => person.id),
          isNot(contains(_offFieldAccountless)),
        );

        await _search(tester, _query);
        wire.expectNameSearch(_query);
        expect(_inRow(_annaRow, 'Anna'), findsOneWidget);
        expect(_accountlessRow(_offFieldAccountless), findsNothing);
        expect(_searchResultRows(tester), findsOneWidget);
        wire.expectNoteSearch(_query);
      });
    },
  );

  testWidgets(
    'a note match for a loaded accountless person excludes an off-Field user',
    (
      tester,
    ) async {
      final wire = _SearchWire(
        userHits: [_offFieldUser],
        accountlessHits: [_kolyaId],
      );
      await _withField(tester, wire, (cubit) async {
        expect(
          cubit.fieldPeople.map((person) => person.id),
          isNot(contains(_offFieldUser)),
        );

        await _search(tester, _query);
        wire.expectNameSearch(_query);
        expect(_inRow(_kolyaRow, 'Kolya'), findsOneWidget);
        expect(_personRow(_offFieldUser), findsNothing);
        expect(_searchResultRows(tester), findsOneWidget);
        wire.expectNoteSearch(_query);
      });
    },
  );

  testWidgets('name and note search start at two characters', (tester) async {
    final wire = _SearchWire(userHits: [_annaId]);
    await _withField(tester, wire, (_) async {
      final input = await _openSearch(tester);
      await tester.enterText(input, 'p');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      final shortQuery = find.byKey(
        const Key('constellation.field_search.short_query'),
      );
      expect(shortQuery, findsOneWidget);
      expect(wire.nameQueries, isEmpty);
      expect(wire.noteQueries, isEmpty);

      await tester.enterText(input, 'pl');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(wire.nameQueries, ['pl']);
      expect(wire.noteQueries, ['pl']);
      expect(shortQuery, findsNothing);
      expect(_inRow(_annaRow, 'Anna'), findsOneWidget);
    });
  });

  testWidgets(
    'typing again restarts the debounce for both name and note search',
    (
      tester,
    ) async {
      final wire = _SearchWire(accountlessHits: [_kolyaId]);
      await _withField(tester, wire, (_) async {
        final input = await _openSearch(tester);
        await tester.enterText(input, 'plu');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(wire.nameQueries, isEmpty);
        expect(wire.noteQueries, isEmpty);

        await tester.enterText(input, 'plum');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 299));
        expect(wire.nameQueries, isEmpty);
        expect(wire.noteQueries, isEmpty);
        expect(_kolyaRow, findsNothing);

        // Name search's 300 ms debounce expires for the final text only.
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(wire.nameQueries, ['plum']);
        expect(wire.noteQueries, ['plum']);
        expect(_inRow(_kolyaRow, 'Kolya'), findsOneWidget);
      });
    },
  );

  testWidgets('a person matching both a name and a note appears once', (
    tester,
  ) async {
    final wire = _SearchWire(userHits: [_annaId], annaNameQuery: 'anna');
    await _withField(tester, wire, (_) async {
      await _search(tester, 'anna');
      wire.expectNameSearch('anna');
      // The only 'Anna' labels counted are in tappable result rows.
      final annaResultLabels = find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Anna'),
      );
      expect(annaResultLabels, findsOneWidget);
      expect(_annaRow, findsOneWidget);
      wire.expectNoteSearch('anna');
    });
  });
}

Finder _personRow(String id) =>
    find.byKey(Key('constellation.field_search.person.$id'));

Finder _accountlessRow(String id) =>
    find.byKey(Key('constellation.field_search.phantom.$id'));

Finder _inRow(Finder row, String text) =>
    find.descendant(of: row, matching: find.text(text));

Finder _searchResultRows(WidgetTester tester) {
  final route = ModalRoute.of(tester.element(find.byType(SearchBar)));
  expect(route, isNotNull);
  return find.byElementPredicate(
    (element) => element.widget is ListTile && ModalRoute.of(element) == route,
  );
}

Future<Finder> _openSearch(WidgetTester tester, {_SearchCopy? copy}) async {
  await tester.tap(_searchButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final input = find.byType(TextField);
  expect(input, findsOneWidget);
  if (copy != null) {
    expect(find.text(copy['constellationFieldSearchHint']), findsOneWidget);
    expect(find.text(copy['constellationFieldSearchPrompt']), findsOneWidget);
    copy.expectRendered(tester);
  }
  return input;
}

Future<void> _search(
  WidgetTester tester,
  String query, {
  _SearchCopy? copy,
}) async {
  final input = await _openSearch(tester, copy: copy);
  await tester.enterText(input, query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

final class _SearchCopy {
  _SearchCopy(Locale locale)
    : current = _readArb(locale.languageCode),
      other = _readArb(locale.languageCode == 'en' ? 'ru' : 'en');

  final Map<String, Object?> current;
  final Map<String, Object?> other;

  String operator [](String key) => current[key]! as String;

  static Map<String, Object?> _readArb(String language) =>
      (jsonDecode(File('l10n/app_$language.arb').readAsStringSync()) as Map)
          .cast<String, Object?>();

  void expectRendered(WidgetTester tester, {Set<String> names = const {}}) {
    final searchRoute = ModalRoute.of(tester.element(find.byType(SearchBar)));
    expect(searchRoute, isNotNull);
    final searchText = find.byElementPredicate(
      (element) =>
          element.widget is Text && ModalRoute.of(element) == searchRoute,
    );
    final labels = {
      for (final text in tester.widgetList<Text>(searchText))
        (text.data ?? text.textSpan!.toPlainText()).trim(),
    }..removeAll({'', ...names});
    expect(labels, isNotEmpty);
    for (final label in labels) {
      expect(
        label,
        isNot(matches(RegExp('phantom|фантом', caseSensitive: false))),
      );
      expect(
        current.entries.any((entry) {
          final value = entry.value;
          final translation = other[entry.key];
          return !entry.key.startsWith('@') &&
              value is String &&
              (label == value || label == value.toUpperCase()) &&
              translation is String &&
              translation.isNotEmpty &&
              translation != value;
        }),
        isTrue,
        reason: '"$label" has a search copy entry in both locales',
      );
    }
  }
}

Future<void> _pick(
  WidgetTester tester,
  ConstellationCubit cubit,
  Finder row, {
  required String graphId,
  required bool person,
}) async {
  final graph = cubit.graphController;
  final position = graph.getPositionOrNullForId(graphId)!;
  final viewport = Offset.zero & graph.viewportSize!;
  final insets = cubit.fieldCameraViewportInsets(
    tester.element(row),
    contextPanelVisible: person,
  );
  final centre = insets.deflateRect(viewport).center;
  graph.jumpToPosition(position + const Offset(800, 800));
  await tester.pump();
  expect(
    (graph.sceneToViewportLocal(position) - centre).distance,
    greaterThan(100),
  );

  await tester.tap(row);
  await tester.pump();
  // The tap centres the camera before the context sheet changes the map's
  // usable viewport. Measure the projection using the viewport at selection.
  final focusedPosition = graph.getPositionOrNullForId(graphId)!;
  final focusedPoint = graph.sceneToViewportLocal(focusedPosition);
  expect(
    (focusedPoint - centre).distance,
    lessThan(16),
    reason: 'The note match is centred in the usable Field viewport',
  );

  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(milliseconds: 1400),
  );

  expect(
    find.byType(SearchBar),
    findsNothing,
    reason: 'The search view closes',
  );
  expect(row, findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _withField(
  WidgetTester tester,
  _SearchWire wire,
  Future<void> Function(ConstellationCubit cubit) check, {
  Locale locale = const Locale('en'),
}) async {
  final phone = locale.languageCode == 'ru';
  final size = phone ? kPhoneSurface : const Size(1200, 900);
  if (phone) await usePhoneSurface(tester);
  // The search overlay is a separate route and reads the window size from View.
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await withRemoteWire(
    const {},
    wire.sent,
    (remote) async {
      final scope = GetIt.I
        ..pushNewScope(
          init: (scope) {
            scope
              ..registerSingleton<RemoteApiService>(remote)
              ..registerSingleton<RemoteRequestClient>(remote)
              ..registerSingleton<PhantomRepositoryPort>(
                PhantomRepository(remote),
              );
          },
        );
      addTearDown(scope.popScope);
      final store = ConstellationStoreFixture(
        _FieldRepository(),
        accountId: _viewer.id,
      ).store;
      final cubit = ConstellationCubit(
        case_: store,
        viewer: _viewer,
        loadOnCreate: false,
        fieldSearchCase: ConstellationFieldSearchCase.withNotes(
          ConstellationFieldSearchRepository(remote),
          PersonNoteRepository(remote),
        ),
      );
      await cubit.load().timeout(const Duration(seconds: 4));
      expect(cubit.state.loadError, isNull);
      expect(cubit.fieldPeople.map((person) => person.id), contains(_annaId));
      expect(cubit.shownField!.phantoms.map((person) => person.id), [_kolyaId]);
      await pumpConstellationBody(
        tester,
        cubit,
        locale: locale,
        size: size,
        disableAnimations: true,
        wrapBody: (body) => Scaffold(
          appBar: AppBar(actions: const [ConstellationPersonSearchButton()]),
          body: body,
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(tester.takeException(), isNull);
      try {
        await check(cubit);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await cubit.close();
      }
    },
    responseFor: wire.respond,
    requestPaths: wire.paths,
  );
}

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    final loadedAt = DateTime.utc(2026, 11, 5);
    return ConstellationField(
      loadedAt: loadedAt,
      context: 'field-context',
      peers: const [ConstellationPerson(id: _annaId, displayName: 'Anna')],
      directContactIds: const [_annaId],
      edges: const [
        ConstellationTrustEdgeEntity(
          src: 'Uviewer000001',
          dst: _annaId,
          tier: 1,
        ),
      ],
      phantoms: [
        Phantom(
          id: _kolyaId,
          displayName: 'Kolya',
          hasPrivateAvatar: false,
          ownTagIds: const [],
          inviteState: PhantomInviteState.none,
          createdAt: loadedAt,
        ),
      ],
    );
  }
}

final class _SearchWire {
  _SearchWire({
    this.annaNameQuery,
    this.userHits = const [],
    this.accountlessHits = const [],
  });

  final sent = <WireSent>[];
  final paths = <String>[];
  final String? annaNameQuery;
  final List<String> userHits;
  final List<String> accountlessHits;

  Iterable<Object?> get nameQueries => sent
      .where((call) => call.operationName == 'FieldSearch')
      .map((call) => call.variables['query']);

  Iterable<Object?> get noteQueries => sent
      .where((call) => call.operationName == 'PersonNoteSearch')
      .map((call) => call.variables['q']);

  Future<Map<String, dynamic>> respond(WireSent request) async =>
      switch (request.operationName) {
        'FieldSearch' => {
          '__typename': 'query_root',
          'fieldSearch': {
            '__typename': 'v2_FieldSearchResult',
            'people': [
              if (request.variables['query'] == annaNameQuery)
                {
                  '__typename': 'v2_FieldSearchPerson',
                  'id': _annaId,
                  'displayName': 'Anna',
                  'handle': null,
                },
            ],
            'requests': <Object>[],
            'posts': <Object>[],
          },
        },
        'PersonNoteSearch' => {
          '__typename': 'query_root',
          'personNoteSearch': [
            for (final id in userHits)
              {
                '__typename': 'PersonNoteSubject',
                'subjectUserId': id,
                'subjectPhantomId': null,
              },
            for (final id in accountlessHits)
              {
                '__typename': 'PersonNoteSubject',
                'subjectUserId': null,
                'subjectPhantomId': id,
              },
          ],
        },
        'PersonNote' => {'__typename': 'query_root', 'personNote': <Object>[]},
        _ => throw StateError(
          'Unexpected GraphQL operation ${request.operationName}',
        ),
      };

  void expectNameSearch(String query) {
    expect(
      nameQueries,
      contains(query),
      reason: 'The normal name search received the query',
    );
  }

  void expectNoteSearch(String query) {
    final index = sent.indexWhere(
      (call) =>
          call.operationName == 'PersonNoteSearch' &&
          call.variables['q'] == query,
    );
    expect(
      index,
      isNonNegative,
      reason: 'Field search also queries private notes',
    );
    expect(paths[index], endsWith('/api/v2/graphql'));
  }
}
