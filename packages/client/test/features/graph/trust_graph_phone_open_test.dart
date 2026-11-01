import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_repository.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// Coverage map for the issue and its member triage comment:
// - Plain first open, without Reset to me/reload: data delivered immediately
//   on the first mounted viewport, independently of untrust or a slow response.
//   Before-layout and delayed after-viewport cases cover the other orderings.
//   Every case has a three-frame visibility deadline.
// - Open after profile untrust: after-untrust cases commit a real UserVote
//   through LikeRemoteRepository before opening the one-way graph, then deliver
//   data on the first mounted viewport with no artificial network delay. This
//   tests opening after withdrawal independently of the slow first-read case.
// - Recheck the current checkout: every case uses the current GraphCubit,
//   GraphRepository and GraphScaffold, with real Ferry decoding/mapping.
// - Existing graph tests (including desktop and subsequent trust updates)
//   remain unchanged; running those belongs to the later regression gate.
// Sibling matrix:
// - Input: n/a, opening needs no canvas input; touch/focus/semantics are not
//   claimed by these widget tests (use the web integration runner for those).
// - Surface: shared Trust GraphScaffold/GraphBody; forwards and invite-tree
//   graphs are separate modes, outside this trust-graph opening regression.
// - Role: signed-in viewer; Request author/helper/invitee roles are n/a.
// - State: mutual trust and one-way trust after withdrawal; Request/Post
//   lifecycle states are n/a because this graph displays people.
// - Freshness: cold open and own committed withdrawal; remote realtime and
//   browser reload/bfcache are n/a to the initial camera visibility contract.
// - Network: data ready before layout, immediately on the first viewport,
//   and held for two seconds after a mounted viewport.
// - Width: 375x667 via usePhoneSurface and matching MediaQuery dimensions;
//   desktop is covered by the unchanged graph regression suite.
// - Locale: every arrival scenario runs in EN and RU, checking complete labels
//   using paragraph paint calls, per-character text bounds and ancestor paint
//   clips; FlutterError diagnostics explicitly reject layout overflow.

const _viewerId = 'Uviewer000001';
const _annaId = 'Uanna00000001';
const _borisId = 'Uboris0000001';

// Only the unused Request dependency is stubbed. People and trust edges pass
// through the real HTTP/Ferry, mapper, repositories, cubit and graph widgets.
class _UnusedBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Request read: ${invocation.memberName}');
}

class _ViewerCubit extends Mock implements ProfileCubit {
  _ViewerCubit(this.state);

  @override
  final ProfileState state;

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _TrustWire {
  final releaseGraph = Completer<void>();
  final operations = <String>[];
  bool viewerTrustsAnna = true;

  Map<String, dynamic> user(String id) => {
    '__typename': 'user',
    'id': id,
    'display_name': switch (id) {
      _annaId => 'Анна',
      _borisId => 'Борис',
      _ => 'Viewer',
    },
    'description': '',
    'handle': null,
    'my_vote': id == _annaId && !viewerTrustsAnna ? 0 : 1,
    'trusts_viewer': true,
    'is_mutual_friend': id != _annaId || viewerTrustsAnna,
    'image': null,
    'scores': <Object>[],
    'user_presence': null,
    'user_availability': null,
  };

  List<Map<String, dynamic>> get edges => [
    for (final peer in [_annaId, _borisId]) ...[
      if (peer != _annaId || viewerTrustsAnna) edge(_viewerId, peer),
      edge(peer, _viewerId),
    ],
  ];

  Map<String, dynamic> edge(String src, String dst) => {
    '__typename': 'graph_score',
    'src': src,
    'dst': dst,
    'src_score': 1.0,
    'dst_score': 1.0,
    'src_total_neighbor_count': src == _viewerId ? 2 : 1,
    'dst_total_neighbor_count': dst == _viewerId ? 2 : 1,
    'user': user(dst),
  };

  Future<http.Response> handle(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final name = body['operationName'] as String;
    final variables = body['variables'] as Map<String, dynamic>;
    operations.add(name);
    final Map<String, dynamic> data;
    switch (name) {
      case 'UserFetchById':
        data = {'user_by_pk': user(variables['id'] as String)};
      case 'UserVote':
        expect(variables['objectId'], _annaId);
        expect(variables['amount'], 0);
        viewerTrustsAnna = false;
        data = {'userVote': 0};
      case 'GraphFetch':
        await releaseGraph.future;
        data = {'graph': edges, 'beacon_by_pk': null};
      case 'GraphEdgesBetween':
        data = {'graph_edges_between': edges};
      default:
        throw StateError('Unexpected operation: $name');
    }
    return _response({'data': data});
  }

  http.Response _response(Map<String, dynamic> value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _mountGraph(
  WidgetTester tester,
  GraphCubit cubit,
  Locale locale,
) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<GraphCubit>.value(value: cubit),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        BlocProvider<ProfileCubit>.value(
          value: _ViewerCubit(ProfileState(profile: cubit.state.me)),
        ),
      ],
      child: Builder(
        builder: (context) => GraphScaffold(
          title: Text(L10n.of(context)!.graphView),
        ),
      ),
    ),
  ),
);

void _expectLabelPainted(
  RenderParagraph paragraph,
  String text,
  Rect viewport,
) {
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.debugHasOverflowShader, isFalse);
  expect(paragraph, paints..paragraph());
  final style = paragraph.text.style;
  expect(
    (style?.foreground?.color ?? style?.color)?.a,
    greaterThan(0),
    reason: '$text must paint with visible ink',
  );

  // These labels contain only single-code-unit letters. Selecting each one
  // individually also detects characters omitted by clipping or ellipsis;
  // a non-empty Text widget or paragraph rectangle cannot prove that.
  for (var offset = 0; offset < text.length; offset++) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    expect(
      boxes,
      isNotEmpty,
      reason: '$text character $offset must be laid out',
    );
    for (final box in boxes) {
      final glyph = box.toRect();
      bool contains(Rect outer, Rect inner) =>
          !inner.isEmpty &&
          outer.inflate(0.001).contains(inner.topLeft) &&
          outer.inflate(0.001).contains(inner.bottomRight);

      expect(
        contains(Offset.zero & paragraph.size, glyph),
        isTrue,
        reason: '$text character $offset at $glyph is clipped by its paragraph',
      );
      final onScreen = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        glyph,
      );
      expect(
        contains(viewport, onScreen),
        isTrue,
        reason: '$text character $offset at $onScreen must be inside $viewport',
      );
      RenderObject child = paragraph;
      while (child.parent != null) {
        final parent = child.parent!;
        expect(
          parent.paintsChild(child),
          isTrue,
          reason: '$text must not be offstage or hidden by an ancestor',
        );
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          final inParent = MatrixUtils.transformRect(
            paragraph.getTransformTo(parent),
            glyph,
          );
          expect(
            contains(clip, inParent),
            isTrue,
            reason:
                '$text character $offset at $inParent is clipped by '
                '${parent.runtimeType} at $clip',
          );
        }
        child = parent;
      }
    }
  }
}

void _expectPeoplePainted(WidgetTester tester, Locale locale) {
  final viewport = tester.getRect(find.byType(GraphBody));
  expect(viewport.width, 375);
  final outside = <String>[];
  for (final entry in {
    _viewerId: locale.languageCode == 'ru' ? 'Я' : 'Me',
    _annaId: 'Анна',
    _borisId: 'Борис',
  }.entries) {
    final marker = find.byKey(TestIds.key(TestIds.graphNode(entry.key)));
    expect(marker, findsOneWidget, reason: '${entry.value} must be painted');
    final label = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.key is ValueKey<UserNode> &&
          (widget.key! as ValueKey<UserNode>).value.id == entry.key,
    );
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).data, entry.value);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    _expectLabelPainted(paragraph, entry.value, viewport);
    for (final part in {'marker': marker, 'label': label}.entries) {
      final rect = tester.getRect(part.value);
      if (rect.isEmpty ||
          !viewport.contains(rect.topLeft) ||
          !viewport.contains(rect.bottomRight)) {
        outside.add('${entry.value} ${part.key}: $rect');
      }
    }
  }
  expect(
    outside,
    isEmpty,
    reason:
        'Me and both neighbours, including their full labels, must be painted '
        'inside $viewport in the first three frames without Reset to me',
  );
}

void main() {
  group('Trust graph opens with people visible on a phone', () {
    for (final locale in [const Locale('en'), const Locale('ru')]) {
      for (final arrival in [
        'before layout',
        'on the first viewport',
        'after a delayed response',
        'after untrust',
      ]) {
        testWidgets(
          'Me and neighbours are in view within three frames when data arrives '
          '$arrival (${locale.languageCode})',
          (tester) async {
            await usePhoneSurface(tester);
            tester.view.physicalSize = kPhoneSurface;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final wire = (await tester.runAsync(() async => _TrustWire()))!;
            await http.runWithClient(() async {
              final remote = RemoteApiService(
                const Env(),
                const WebSocketClientRealtimeSocketFactory(),
              );
              final profiles = ProfileRepository(remote);
              final likes = LikeRemoteRepository(
                remoteApiService: remote,
                log: Logger('TrustPhoneWrite'),
              );
              GraphCubit? graph;
              final flutterDiagnostics = <String>[];
              final previousErrorHandler = FlutterError.onError;
              FlutterError.onError = (details) {
                // RenderFlex overflow is reported through FlutterError even
                // when it is not surfaced as a thrown layout exception.
                flutterDiagnostics.add(details.toString());
                previousErrorHandler?.call(details);
              };
              try {
                // Cookie-session auth uses native browser fetch and bypasses
                // http.runWithClient. Seeded auth keeps this graph-only test
                // on the same mocked GraphQL transport on Chrome and the VM.
                await tester.runAsync(
                  () => remote.setAuth(
                    seed: base64Encode(List<int>.filled(32, 0)),
                    authTokenFetcher: (_, _) async => Credentials(
                      userId: _viewerId,
                      accessToken: 'test-token',
                      expiresAt: DateTime.timestamp().add(
                        const Duration(hours: 1),
                      ),
                    ),
                  ),
                );
                final me = (await tester.runAsync(
                  () => profiles.fetchById(_viewerId),
                ))!;
                if (arrival == 'after untrust') {
                  await tester.runAsync(() async {
                    final anna = await profiles.fetchById(_annaId);
                    expect(anna.myVote, 1);
                    final changed = await likes.setLike(anna, amount: 0);
                    expect(changed.myVote, 0);
                  });
                  expect(wire.operations, contains('UserVote'));
                  expect(wire.viewerTrustsAnna, isFalse);
                  expect(wire.operations, isNot(contains('GraphFetch')));
                }
                // Construct in the real async zone so HTTP deadlines remain
                // real; only the response gate controls delivery to the UI.
                await tester.runAsync(() async {
                  graph = GraphCubit(
                    me: me,
                    graphSourceRepository: GraphRepository(
                      remoteApiService: remote,
                      log: Logger('TrustPhoneGraph'),
                    ),
                    profileRepository: profiles,
                    personTrustWrites: likes,
                    beaconRepository: _UnusedBeaconRepository(),
                    edgeColors: GraphEdgeColors.fromTokens(
                      TenturaTheme.light().extension<TenturaTokens>()!,
                    ),
                    effects: FakeUiEffectPort(),
                  );
                });
                final cubit = graph!;
                Future<void> deliver() async {
                  await tester.runAsync(() async {
                    final loaded = cubit.stream.firstWhere(
                      (state) => !state.isLoading,
                    );
                    wire.releaseGraph.complete();
                    await loaded.timeout(
                      const Duration(seconds: 5),
                      onTimeout: () => throw StateError(
                        'Graph did not finish loading; requests: ${wire.operations}',
                      ),
                    );
                  });
                  expect(cubit.state.status, StateStatus.isSuccess);
                  expect(
                    wire.operations,
                    containsAll([
                      'GraphFetch',
                      'GraphEdgesBetween',
                    ]),
                  );
                  expect(cubit.graphController.nodes, hasLength(3));
                  if (arrival == 'after untrust') {
                    expect(
                      wire.operations.indexOf('UserVote'),
                      lessThan(wire.operations.indexOf('GraphFetch')),
                      reason:
                          'the withdrawal must commit before opening the graph',
                    );
                    expect(cubit.viewerLink(_annaId), (
                      fromViewer: null,
                      toViewer: 1.0,
                    ));
                  }
                }

                if (arrival == 'before layout') {
                  await deliver();
                  expect(cubit.graphController.viewportSize, isNull);
                  await _mountGraph(tester, cubit, locale);
                } else {
                  final mountedAt = tester.binding.clock.now();
                  await _mountGraph(tester, cubit, locale);
                  expect(tester.getSize(find.byType(GraphBody)).width, 375);
                  expect(cubit.graphController.viewportSize, isNotNull);
                  if (arrival == 'after a delayed response') {
                    // A slow first read: the viewport exists for two seconds
                    // before the server answers, without any camera input.
                    await tester.pump(const Duration(seconds: 2));
                    expect(
                      tester.binding.clock.now().difference(mountedAt),
                      const Duration(seconds: 2),
                    );
                  } else {
                    // Both fresh and post-withdrawal opens have a ready
                    // response on the first viewport, independent of the
                    // separately tested two-second network delay.
                    expect(
                      tester.binding.clock.now().difference(mountedAt),
                      Duration.zero,
                    );
                    if (arrival == 'on the first viewport') {
                      expect(wire.operations, isNot(contains('UserVote')));
                    }
                  }
                  expect(cubit.state.isLoading, isTrue);
                  expect(cubit.graphController.nodes, isEmpty);
                  await deliver();
                }
                for (var frame = 0; frame < 3; frame++) {
                  // Delivery starts layout work in runAsync's real zone.
                  // Fake-clock pumps alone cannot drain that event queue.
                  await tester.runAsync(pumpEventQueue);
                  await tester.pump(const Duration(milliseconds: 16));
                }
                expect(
                  flutterDiagnostics,
                  isEmpty,
                  reason:
                      'The 375x667 ${locale.languageCode} graph must report no '
                      'Flutter errors, including layout overflow diagnostics',
                );
                expect(tester.takeException(), isNull);
                _expectPeoplePainted(tester, locale);
              } finally {
                FlutterError.onError = previousErrorHandler;
                if (!wire.releaseGraph.isCompleted) {
                  wire.releaseGraph.complete();
                }
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.runAsync(() async {
                  await graph?.close();
                  await likes.dispose();
                  await profiles.dispose();
                  await remote.close();
                });
              }
            }, () => MockClient(wire.handle));
          },
        );
      }
    }
  });
}
