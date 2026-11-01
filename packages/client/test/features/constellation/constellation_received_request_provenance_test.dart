@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

// Coverage: map placement, map-label and list provenance, counts, EN desktop,
// and RU 375x667. Each surface/locale has an independent red test, so a
// list-only fix cannot hide the map failure.
// Input n/a: static rendering, no gesture/focus/semantics claim. Role: recipient
// of an open Request; author/helper permissions, Posts and terminal states
// use different policies. Freshness: cold read; realtime/reload out of scope.
// Network: successful response; loading/error behavior is not changed.
// No pins: forwarding must work without relaxing rev 10 section 5.10.
// The server PG contract test verifies the response against the real incoming
// edge and its sender profile. Query-selection tests below independently
// verify both the source and generated production operation. Additive fields use
// the existing PostSummary forwardedById/forwardedByName naming convention.
const _viewer = Profile(id: 'Uviewer000001', displayName: 'Zed');
const _bob = 'Uforwardbob01';
const _alice = 'Uauthoralice1';
const _request = 'Bforwarded001';

Map<String, dynamic> _response() =>
    jsonDecode(
          File(
            'test/support/fixtures/received_request_field_response.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Set<String> _selectedFields(DocumentNode document, List<String> path) {
  final fragments = {
    for (final fragment
        in document.definitions.whereType<FragmentDefinitionNode>())
      fragment.name.value: fragment.selectionSet,
  };
  Iterable<FieldNode> fields(SelectionSetNode selection) sync* {
    for (final node in selection.selections) {
      if (node is FieldNode) {
        yield node;
      } else if (node is InlineFragmentNode) {
        yield* fields(node.selectionSet);
      } else if (node is FragmentSpreadNode) {
        yield* fields(fragments[node.name.value]!);
      }
    }
  }

  var selection = document.definitions
      .whereType<OperationDefinitionNode>()
      .single
      .selectionSet;
  for (final name in path) {
    selection = fields(selection)
        .singleWhere(
          (field) => field.name.value == name,
        )
        .selectionSet!;
  }
  return fields(selection).map((field) => field.name.value).toSet();
}

void _expectFullProvenance(
  WidgetTester tester,
  Finder surface, {
  required String locale,
  required Size viewport,
}) {
  final expected = locale == 'ru' ? 'Переслано: Bob' : 'Forwarded by Bob';
  final wrong = locale == 'ru'
      ? 'Вы переслали этот запрос'
      : 'You forwarded this request';
  final texts = find.descendant(of: surface, matching: find.byType(Text));
  final visibleText = tester
      .widgetList<Text>(texts)
      .map(
        (text) => text.data ?? text.textSpan?.toPlainText() ?? '',
      );
  // Compare entire localized lines, permitting either a separate status Text
  // or a second line in the title Text. Incidental mentions of Bob do not pass.
  expect(
    visibleText.any((text) => text.contains(wrong)),
    isFalse,
    reason: 'Zed received this Request; Bob forwarded it.',
  );
  final provenance = texts.evaluate().where((element) {
    final text = element.widget as Text;
    return (text.data ?? text.textSpan?.toPlainText() ?? '')
        .split('\n')
        .contains(expected);
  }).toList();
  expect(
    provenance,
    hasLength(1),
    reason: 'The sender relationship must read exactly "$expected".',
  );
  final text = find.byWidget(provenance.single.widget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'The complete sender line must fit, including on the RU phone.',
  );
  final bounds = tester.getRect(text);
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(viewport.width));
  expect(bounds.top, greaterThanOrEqualTo(0));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.height));
  expect(
    tester.takeException(),
    isNull,
    reason: 'No other widget may overflow after the sender line is rendered.',
  );
}

void main() {
  group('The Field query fetches the received-forward sender', () {
    for (final entry in {
      'Requests': ['constellationField', 'requests'],
      'pinned Requests': [
        'constellationField',
        'anchorProjection',
        'pinnedRequests',
      ],
    }.entries) {
      test('selects the forwarding contact identity and name for ${entry.key}', () {
        // The response fixture cannot prove what a real server would return:
        // check the selections in both the source and the actual Ferry request
        // used by ConstellationRepository. Stale codegen also stays red.
        final documents = {
          'source query': parseString(
            File(
              'lib/features/constellation/data/gql/constellation_field_fetch.graphql',
            ).readAsStringSync(),
          ),
          'Ferry request': GConstellationFieldFetchReq((builder) {
            builder.vars
              ..showClosed = false
              ..participatedOnly = false
              ..projection = Gv2_ConstellationProjection.FULL;
          }).operation.document,
        };
        for (final document in documents.entries) {
          expect(
            _selectedFields(document.value, entry.value),
            containsAll(['forwardedById', 'forwardedByName']),
            reason:
                '${document.key} must request the incoming sender for ${entry.key}; '
                'extra fields in a mock response cannot substitute for a selection.',
          );
        }
      });
    }
  });

  group('A Request received through a contact', () {
    for (final locale in ['en', 'ru']) {
      for (final surface in ['map', 'list']) {
        testWidgets(
          'names the forwarder on the $surface in $locale while keeping the '
          'Request on both surfaces',
          (tester) async {
            final size = locale == 'ru' ? kPhoneSurface : const Size(1280, 900);
            if (locale == 'ru') await usePhoneSurface(tester);
            final sent = <WireSent>[];
            late ConstellationCubit cubit;
            await tester.runAsync(
              () => withRemoteWire(
                {'ConstellationFieldFetch': _response()},
                sent,
                (remote) async {
                  final store = ConstellationStoreFixture(
                    ConstellationRepository(remote),
                    accountId: _viewer.id,
                  );
                  cubit = store.createCubit(viewer: _viewer);
                  await store.ready();
                  await cubit.load().timeout(const Duration(seconds: 15));
                },
              ),
            );
            expect(
              sent.map((request) => request.operationName),
              contains('ConstellationFieldFetch'),
            );
            final field = cubit.state.field!;
            expect(field.directContactIds, [_bob]);
            expect(
              field.edges.map((edge) => (edge.src, edge.dst)),
              unorderedEquals([(_viewer.id, _bob), (_bob, _viewer.id)]),
            );
            final author = field.peers.singleWhere((peer) => peer.id == _alice);
            expect(
              author.fieldMembership,
              ConstellationFieldMembership.temporary,
            );
            expect(author.temporaryBeaconId, _request);
            // Alice is NOT an ordinary visible/direct peer. The PG companion
            // proves that the reader recognizes the explicit Zed-Bob-Alice trust path.
            final request = field.requests.singleWhere((r) => r.id == _request);
            expect(request.authorId, _alice);
            expect(request.viewerHasForwardEdge, isTrue);
            expect(request.isMine, isFalse);
            expect(cubit.visibilityCounts!.requests, 1);

            await pumpConstellationBody(
              tester,
              cubit,
              size: size,
              locale: Locale(locale),
              disableAnimations: true,
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'The map must render without overflow at this viewport.',
            );
            final positions =
                cubit.graphController.renderSnapshot.layout!.positions;
            for (final id in ['fp:$_alice', 'fr:$_request']) {
              expect(positions.keys, contains(id));
              final position = positions[id]!;
              expect(position.x.isFinite && position.y.isFinite, isTrue);
            }
            expect(cubit.displayedRequestIds, contains(_request));
            final mapLabel = find.byKey(
              const ValueKey('constellation.label.fr:$_request'),
            );
            expect(mapLabel, findsOneWidget);
            // Capture what the mounted map label actually renders before
            // switching surfaces; no standalone substitute label is mounted.
            final mapText = tester
                .widgetList<Text>(
                  find.descendant(
                    of: mapLabel,
                    matching: find.byType(Text),
                  ),
                )
                .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
                .join('\n');
            expect(mapText.split('\n'), contains('Move the piano'));

            cubit.setViewMode(ConstellationViewMode.text);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'The Field list must render without overflow, including RU phone.',
            );
            final card = find.byKey(
              const Key('constellation.text.request.$_request'),
            );
            expect(card, findsOneWidget);
            expect(
              find.descendant(of: card, matching: find.text('Move the piano')),
              findsOneWidget,
            );

            if (surface == 'map') {
              cubit.setViewMode(ConstellationViewMode.map);
              await tester.pumpAndSettle();
              // Map layout includes offscreen nodes and preserves camera pan.
              // Bring this Request into view before checking viewport bounds.
              await cubit.graphController.jumpToNodeId('fr:$_request');
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'Returning to map mode must not overflow.',
              );
              _expectFullProvenance(
                tester,
                mapLabel,
                locale: locale,
                viewport: size,
              );
            } else {
              _expectFullProvenance(
                tester,
                card,
                locale: locale,
                viewport: size,
              );
            }
          },
        );
      }
    }
  });
}
