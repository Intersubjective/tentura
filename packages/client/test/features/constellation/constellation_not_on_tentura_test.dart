@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAnimatedOpacity, RenderOpacity;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/database/database.dart' show Database, Value;
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_visibility_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_visibility.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_search_result.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_search_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_search_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_temporary_outline.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _member = 'Umember000001';
const _temporary = 'Utemporary001';
const _request = 'Rladder000001';
const _post = 'Pgarden000001';
const _peopleNotOnTentura = [
  ('PH0123456789ab', 'Anna Petrova'),
  ('PH1234567890ab', 'Boris'),
  ('PH2345678901ab', 'Cleo'),
];
final _otherGraphIds = {
  'fp:${_viewer.id}',
  'fp:$_member',
  'fp:$_temporary',
  'fr:$_request',
  'fr:$_post',
};
const _otherChips = [
  'requests',
  'posts',
  'degree.first',
  'degree.second',
  'degree.further',
];
final _now = DateTime.utc(2026, 11, 12, 10);

Finder _tile(String graphId) => find.byKey(ValueKey(graphId));
Finder _chip(String kind) => find.byKey(Key('constellation.show.$kind'));
Finder _chipCount(String kind) =>
    find.byKey(Key('constellation.show.$kind.count'));
Finder _inside(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);
Finder _listText(String text) =>
    _inside(find.byType(ConstellationTextView), find.text(text));

Future<void> _switchView(WidgetTester tester, String identifier) async {
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.identifier == identifier,
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _peer(
  String id,
  String name, {
  bool temporary = false,
}) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'displayName': name,
  'contactOnly': false,
  'presence': temporary ? 'temporary' : 'visible',
  'temporaryBeaconId': temporary ? _request : null,
  'bondContexts': <Object?>[],
  'isNew': false,
};

Map<String, dynamic> _fieldResponse(
  List<(String, String)> people, {
  required bool includeOtherItems,
}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': _now.toIso8601String(),
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [if (includeOtherItems) _member],
    'peers': [
      if (includeOtherItems) ...[
        _peer(_member, 'Annabel Reed'),
        _peer(_temporary, 'Tamsin', temporary: true),
      ],
    ],
    'edges': [
      if (includeOtherItems)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': _viewer.id,
          'dst': _member,
          'tier': 1,
        },
    ],
    'requests': [
      if (includeOtherItems)
        {
          '__typename': 'v2_ConstellationRequest',
          'id': _request,
          'authorId': _temporary,
          'title': 'Borrow a ladder',
          'status': 0,
          'needs': <String>[],
          'lastActivityAt': _now.toIso8601String(),
          'hasCoordinates': false,
          'isMine': false,
          'viewerHasActiveHelpOffer': false,
          'viewerIsRoomParticipant': false,
          'viewerHasForwardEdge': false,
          'helpOfferCount': 0,
          'coverSource': 0,
          'has_unread': false,
        },
    ],
    'posts': [
      if (includeOtherItems)
        {
          '__typename': 'v2_ConstellationPost',
          'id': _post,
          'authorId': _member,
          'lastActivityAt': _now.toIso8601String(),
          'status': 0,
          'rootExcerpt': 'Garden meetup',
          'isPinned': false,
          'hiddenReachCount': 0,
          'has_unread': false,
        },
    ],
    'memberWebs': <Object?>[],
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
    'phantoms': [
      for (final (id, name) in people)
        {
          '__typename': 'v2_ConstellationPhantom',
          'id': id,
          'displayName': name,
          'emoji': '🌿',
          'hasPrivateAvatar': false,
          'ownTagIds': <String>[],
          'inviteState': 'none',
          'createdAt': _now.toIso8601String(),
        },
    ],
  },
};

// The online person directory only knows about registered accounts.
class _Directory implements ConstellationFieldSearchPort {
  @override
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) async => query.toLowerCase() == 'ann'
      ? const ConstellationFieldSearchResult(
          people: [
            ConstellationFieldSearchPersonHit(
              id: _member,
              displayName: 'Annabel Reed',
            ),
          ],
        )
      : emptyConstellationFieldSearchResult;
}

class _Account implements ConstellationAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer.id);
}

Future<ConstellationCubit> _mount(
  WidgetTester tester, {
  List<(String, String)> people = _peopleNotOnTentura,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  bool includeOtherItems = true,
}) async {
  const operation = 'ConstellationFieldFetch';
  final sent = <WireSent>[];
  final cubit = (await tester.runAsync(
    () => _loadField(
      operation,
      _fieldResponse(people, includeOtherItems: includeOtherItems),
      sent,
    ),
  ))!;
  expect(sent.map((call) => call.operationName), contains(operation));
  expect(cubit.state.loadError, isNull);
  expect(
    cubit.state.field?.phantoms.map(
      (person) => (person.id, person.displayName),
    ),
    unorderedEquals(people),
    reason: 'The GraphQL records must reach the Field before testing its UI',
  );

  final phone = locale.languageCode == 'ru';
  if (phone) await usePhoneSurface(tester);
  await pumpConstellationBody(
    tester,
    cubit,
    size: phone ? kPhoneSurface : const Size(1240, 900),
    locale: locale,
    theme: theme,
    disableAnimations: true,
    wrapBody: (body) => Column(
      children: [
        ConstellationAppBarRow(legendExpanded: false, onToggleLegend: () {}),
        Expanded(child: body),
      ],
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return cubit;
}

Future<ConstellationCubit> _loadField(
  String operation,
  Map<String, dynamic> response,
  List<WireSent> sent,
) async {
  late ConstellationCubit cubit;
  await withRemoteWire({operation: response}, sent, (
    remote,
  ) async {
    final realtime = buildTestRealtimeSync();
    final store = ConstellationFieldStoreCase(
      ConstellationRepository(remote),
      _Account(),
      FakeClockPort(_now),
      FakeWakeUpPort(),
      realtime.case_,
      env: const Env.fromEnvironment(),
      logger: Logger.detached('FieldWireTest'),
      phantomsEnabled: true,
    );
    cubit = ConstellationCubit(
      case_: store,
      viewer: _viewer,
      loadOnCreate: false,
      fieldSearchCase: ConstellationFieldSearchCase(_Directory()),
    );
    addTearDown(() async {
      await cubit.close();
      await store.dispose();
      await realtime.port.dispose();
    });
    await Future<void>.delayed(Duration.zero);
    await cubit.load().timeout(const Duration(seconds: 4));
  });
  return cubit;
}

Set<String> _graphIds(ConstellationCubit cubit) =>
    cubit.graphController.nodes.map((node) => node.graphNodeId).toSet();

String? _count(WidgetTester tester, String kind) {
  final finder = _chipCount(kind);
  return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
}

Set<String> _renderedIds(Iterable<String> ids) => {
  for (final id in ids)
    if (_tile(id).evaluate().isNotEmpty) id,
};

Finder _ghostBadge(Finder tile) =>
    _inside(tile, find.byKey(const Key('constellation.phantom.ghost_badge')));

/// Record what the node actually draws, without sampling pixels or prescribing
/// whether the outline uses a decoration, oval, or custom path.
typedef _Stroke = ({Color color, List<double> contours});

List<_Stroke> _strokes(WidgetTester tester, Finder marker) {
  final strokes = <_Stroke>[];
  expect(
    tester.renderObject(marker),
    paints..everything((method, arguments) {
      if (!{
        #drawPath,
        #drawCircle,
        #drawOval,
        #drawRRect,
        #drawDRRect,
      }.contains(method)) {
        return true;
      }
      final paint = arguments.last as Paint;
      if (paint.style != PaintingStyle.stroke && method != #drawDRRect) {
        return true;
      }
      strokes.add((
        color: paint.color.withValues(alpha: 1),
        contours: method == #drawPath
            ? _relativeContours(arguments.first as Path)
            : const [],
      ));
      return true;
    }),
  );
  return strokes;
}

List<double> _relativeContours(Path path) {
  final diameter = path.getBounds().longestSide;
  return [
    for (final contour in path.computeMetrics()) contour.length / diameter,
  ];
}

bool _sameDashPattern(List<double> temporary, List<double> candidate) =>
    temporary.length > 1 &&
    temporary.length == candidate.length &&
    Iterable<int>.generate(temporary.length).every(
      (index) => (temporary[index] - candidate[index]).abs() < 0.005,
    );

double _opacity(WidgetTester tester, Finder node) {
  var opacity = 1.0;
  void visit(RenderObject renderObject, double inherited) {
    final alpha = switch (renderObject) {
      RenderOpacity(:final opacity) => opacity,
      RenderAnimatedOpacity(:final opacity) => opacity.value,
      _ => 1.0,
    };
    final effective = alpha * inherited;
    if (effective < opacity) opacity = effective;
    renderObject.visitChildren((child) => visit(child, effective));
  }

  visit(tester.renderObject(node), 1);
  return opacity;
}

bool _hasSelection(Finder node) => _inside(
  node,
  find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.selected == true,
  ),
).evaluate().isNotEmpty;

void main() {
  final phantoms = _peopleNotOnTentura
      .map((person) => 'fh:${person.$1}')
      .toSet();
  final anna = _peopleNotOnTentura.first;
  final annaNode = _tile('fh:${anna.$1}');
  final names = _peopleNotOnTentura.map((person) => person.$2).toList();
  final privateTerms = RegExp('phantom|фантом', caseSensitive: false);
  const listMode = TestIds.constellationAppBarViewModeText;
  const mapMode = TestIds.constellationAppBarViewModeMap;
  const fieldCopy = [
    (Locale('en'), 'Not on Tentura yet', ['Not here yet']),
    (
      Locale('ru'),
      'Ещё не в Тентуре',
      ['Пока не здесь', 'Ещё не здесь', 'Еще не здесь'],
    ),
  ];

  test(
    'English and Russian catalogs provide Field copy without internal terms',
    () {
      final forbidden = <String>[];
      final missing = <String>[];
      for (final (locale, status, chipLabels) in fieldCopy) {
        final path = 'l10n/app_${locale.languageCode}.arb';
        final catalog =
            jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
        final messages = {
          for (final MapEntry(:key, :value) in catalog.entries)
            if (!key.startsWith('@') && value is String) key: value,
        };
        forbidden.addAll([
          for (final MapEntry(:key, :value) in messages.entries)
            if (privateTerms.hasMatch(value)) '$path $key',
        ]);
        if (!messages.containsValue(status)) {
          missing.add('$path needs the List status «$status»');
        }
        if (!chipLabels.any(messages.containsValue)) {
          missing.add('$path needs a filter label from $chipLabels');
        }
      }
      expect(
        forbidden,
        isEmpty,
        reason: 'User-facing messages use public terminology',
      );
      expect(
        missing,
        isEmpty,
        reason: 'Both locales supply the Field messages',
      );
    },
  );

  testWidgets(
    'Field graph ids keep people without accounts distinct from other node kinds',
    (
      tester,
    ) async {
      const request = ConstellationRequest(
        id: 'abc',
        authorId: _member,
        title: 'Borrow a ladder',
        status: 0,
      );
      const person = FieldPersonNode(
        person: Profile(id: 'abc'),
        ring: 1,
        isKept: false,
      );
      const draft = FieldDraftNode();
      final cubit = await _mount(
        tester,
        people: [
          ('abc', anna.$2),
          (draft.id, 'Boris'),
        ],
      );
      final byName = {
        for (final node in cubit.graphController.nodes) node.label: node,
      };
      final annaPayload = byName[anna.$2];
      final borisPayload = byName['Boris'];
      expect(
        [annaPayload?.graphNodeId, borisPayload?.graphNodeId],
        ['fh:abc', 'fh:${draft.id}'],
      );
      expect(annaPayload?.runtimeType.toString(), 'FieldPhantomNode');
      expect(annaPayload?.graphNodeId, isNot(person.graphNodeId));
      expect(
        annaPayload?.graphNodeId,
        isNot(const FieldBeaconNode(request: request).graphNodeId),
      );
      expect(borisPayload?.graphNodeId, isNot(draft.graphNodeId));
    },
  );

  for (final (locale, status, chipLabels) in fieldCopy) {
    testWidgets(
      'Field records appear on the map, List and count chip in ${locale.languageCode}',
      (
        tester,
      ) async {
        final cubit = await _mount(tester, locale: locale);
        final graphIds = _graphIds(cubit);
        expect(graphIds, containsAll(_otherGraphIds));
        final onMap = _renderedIds(phantoms);
        final chip = _chip('phantoms');
        final label = _inside(chip, find.byType(Text))
            .evaluate()
            .map((element) => (element.widget as Text).data)
            .where((text) => text != null && text != '3')
            .join();
        final tooltip = find.ancestor(of: chip, matching: find.byType(Tooltip));
        final count = _count(tester, 'phantoms');

        await _switchView(tester, listMode);
        expect(find.byType(ConstellationTextView), findsOneWidget);
        expect(_listText('Annabel Reed'), findsOneWidget);
        for (final (id, _) in _peopleNotOnTentura) {
          expect(
            find.byKey(Key('constellation.text.person_row.$id')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);

        expect(onMap, unorderedEquals(phantoms));
        expect(count, '3');
        for (final name in names) {
          expect(_listText(name), findsOneWidget);
        }
        expect(_listText(status), findsNWidgets(3));
        expect(_graphIds(cubit), containsAll(phantoms));
        expect(tester.widget<FilterChip>(chip).selected, isTrue);
        expect(label, isIn(chipLabels));
        expect(label, isNot(matches(privateTerms)));
        for (final widget in tester.widgetList<Tooltip>(tooltip)) {
          expect(widget.message ?? '', isNot(matches(privateTerms)));
        }
      },
    );
  }

  testWidgets(
    'the count chip hides and restores people without accounts on both views',
    (
      tester,
    ) async {
      final cubit = await _mount(tester);
      final chip = _chip('phantoms');
      final allIds = {..._otherGraphIds, ...phantoms};
      final counts = {
        for (final kind in _otherChips) kind: _count(tester, kind),
      };
      expect(counts, containsPair('requests', '1'));
      expect(counts, containsPair('posts', '1'));
      expect(counts, containsPair('degree.first', '1'));

      expect(
        chip,
        findsOneWidget,
        reason: 'Three people without accounts can be hidden',
      );
      expect(_graphIds(cubit), allIds);
      expect(_renderedIds(allIds), allIds);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isFalse);
      expect(cubit.state.visibility.toJson()['phantoms'], isFalse);
      expect(_graphIds(cubit), _otherGraphIds);
      expect(_renderedIds(allIds), _otherGraphIds);
      expect(_count(tester, 'phantoms'), '3');
      expect({
        for (final kind in _otherChips) kind: _count(tester, kind),
      }, counts);

      await _switchView(tester, listMode);
      for (final text in ['Annabel Reed', 'Borrow a ladder', 'Garden meetup']) {
        expect(_listText(text), findsOneWidget);
      }
      for (final name in names) {
        expect(_listText(name), findsNothing);
      }
      expect(_count(tester, 'phantoms'), '3');

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
      expect(cubit.state.visibility.toJson()['phantoms'], isTrue);
      for (final name in names) {
        expect(_listText(name), findsOneWidget);
      }
      await _switchView(tester, mapMode);
      expect(_graphIds(cubit), allIds);
      expect(_renderedIds(allIds), allIds);
      expect({
        for (final kind in _otherChips) kind: _count(tester, kind),
      }, counts);
    },
  );

  testWidgets(
    'the count chip is reserved for Fields with people without accounts',
    (
      tester,
    ) async {
      await _mount(tester, people: []);
      final chip = _chip('phantoms');
      expect(_chip('requests'), findsOneWidget);
      expect(chip, findsNothing);

      await _mount(tester, includeOtherItems: false);
      expect(chip, findsOneWidget);
      expect(_count(tester, 'phantoms'), '3');
    },
  );

  testWidgets(
    'name search matches people without accounts and jumps to their Field node',
    (
      tester,
    ) async {
      final cubit = await _mount(tester);
      await tester.tap(find.byKey(const Key('constellation.app_bar.search')));
      await tester.pumpAndSettle();
      final input = find.byType(EditableText);
      final result = find.text(anna.$2).hitTestable();
      expect(input, findsOneWidget);

      await tester.enterText(input, 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.field_search.empty')),
        findsOneWidget,
      );
      for (final name in names) {
        expect(find.text(name).hitTestable(), findsNothing);
      }
      for (final query in ['ann', 'aNN']) {
        await tester.enterText(input, query);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('constellation.field_search.person.$_member')),
          findsOneWidget,
        );
        expect(result, findsOneWidget, reason: 'Query: $query');
        expect(find.text('Boris').hitTestable(), findsNothing);
      }

      final cameraBefore = cubit.graphController.cameraRevision.value;
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(annaNode.hitTestable(), findsOneWidget);
      final graph = cubit.graphController;
      final position = graph.getPositionOrNullForId('fh:${anna.$1}');
      final insets = cubit.fieldCameraViewportInsets(
        tester.element(find.byType(ConstellationAppBarRow)),
        contextPanelVisible: true,
      );
      final viewport = Offset.zero & graph.viewportSize!;
      final centres = [viewport.center, insets.deflateRect(viewport).center];
      expect(
        _hasSelection(annaNode) ||
            (position != null &&
                graph.cameraRevision.value > cameraBefore &&
                centres.any(
                  (centre) =>
                      (graph.sceneToViewportLocal(position) - centre).distance <
                      60,
                )),
        isTrue,
        reason:
            'Picking the result selects the corresponding node or centres it',
      );
    },
  );

  testWidgets(
    'map nodes for people without accounts use their theme outline and carry a ghost badge',
    (
      tester,
    ) async {
      final colors = <Color>[];
      for (final theme in [TenturaTheme.light(), TenturaTheme.dark()]) {
        final cubit = await _mount(tester, theme: theme);
        final graph = cubit.graphController;
        graph.zoomBy(1.0 / graph.cameraScale);
        await tester.pumpAndSettle();
        final member = _tile('fp:$_member');
        final temporary = _tile('fp:$_temporary');
        expect(member, findsOneWidget);
        expect(temporary, findsOneWidget);
        final dashes = _inside(
          temporary,
          find.byType(ConstellationTemporaryOutline),
        );
        expect(dashes, findsOneWidget);
        final tempPaths = _strokes(tester, dashes);
        expect(tempPaths.any((stroke) => stroke.contours.length > 1), isTrue);
        expect(_ghostBadge(member), findsNothing);
        expect(_ghostBadge(temporary), findsNothing);

        expect(annaNode, findsOneWidget);
        expect(_ghostBadge(annaNode), findsOneWidget);
        expect(
          _inside(annaNode, find.byType(ConstellationTemporaryOutline)),
          findsNothing,
        );

        final tokens =
            theme.extension<TenturaTokens>() ??
            (throw TestFailure('Tentura theme tokens are missing'));
        final color = tokens.graphPhantomAccent.withValues(alpha: 1);
        expect(HSVColor.fromColor(color).hue, inInclusiveRange(245.0, 315.0));
        colors.add(color);
        final recordedStrokes = _strokes(tester, annaNode);
        // Paint round-trips its channels through float32. Compare the same
        // 8-bit sRGB values used to define the palette.
        final strokes = recordedStrokes.where(
          (stroke) => stroke.color.toARGB32() == color.toARGB32(),
        );
        expect(
          strokes,
          isNotEmpty,
          reason: 'The outline uses $color. Recorded strokes: $recordedStrokes',
        );
        for (final stroke in strokes) {
          expect(
            tempPaths.any(
              (path) => _sameDashPattern(path.contours, stroke.contours),
            ),
            isFalse,
            reason:
                'The outline for a person without an account differs from the temporary-person dashes',
          );
        }
      }
      expect(colors.first, isNot(colors.last));
    },
  );

  testWidgets(
    'selecting a node for a person without an account restores full opacity until cleared',
    (
      tester,
    ) async {
      await _mount(tester);
      expect(annaNode.hitTestable(), findsOneWidget);
      final idle = _opacity(tester, annaNode);
      expect(idle, inExclusiveRange(0.0, 1.0));

      final mouse = await tester.startGesture(
        tester.getCenter(annaNode),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.up();
      await mouse.moveTo(
        tester.getTopLeft(find.byType(ConstellationAppBarRow)),
      );
      await tester.pumpAndSettle();
      expect(_opacity(tester, annaNode), 1.0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_opacity(tester, annaNode), idle);
    },
  );

  testWidgets(
    'mouse hover brightens an unselected node for a person without an account until exit',
    (
      tester,
    ) async {
      await _mount(tester);
      expect(annaNode.hitTestable(), findsOneWidget);
      final idle = _opacity(tester, annaNode);
      expect(idle, inExclusiveRange(0.0, 1.0));

      final outside = tester.getTopLeft(find.byType(ConstellationAppBarRow));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: outside);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(annaNode));
      await tester.pumpAndSettle();
      expect(_opacity(tester, annaNode), 1.0);
      await mouse.moveTo(outside);
      await tester.pumpAndSettle();
      expect(_opacity(tester, annaNode), idle);
    },
  );

  test(
    'device settings round-trip visibility and keep it separate per viewer',
    () async {
      final db = Database(
        const Env(),
        Logger.detached('VisibilityTest'),
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final repository = ConstellationVisibilityRepository(db);
      const legacyViewer = 'legacy-viewer';
      final hidden = ConstellationVisibility.fromJson(const {
        'phantoms': false,
        'requests': false,
      });
      await repository.write(viewerId: _viewer.id, visibility: hidden);
      await db.managers.settings.create(
        (row) => row(
          key: ConstellationVisibilityRepository.storageKey(legacyViewer),
          valueText: Value(jsonEncode({'posts': false})),
        ),
      );

      final restored = await repository.read(viewerId: _viewer.id);
      final legacy = await repository.read(viewerId: legacyViewer);
      expect(restored?.requests, isFalse);
      expect(legacy?.posts, isFalse);
      expect(
        [restored?.toJson()['phantoms'], legacy?.toJson()['phantoms']],
        [false, true],
        reason:
            'Off survives a JSON round-trip and older settings default to shown',
      );
    },
  );
}
