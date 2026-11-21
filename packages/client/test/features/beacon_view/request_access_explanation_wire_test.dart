import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_screen_harness.dart';
import 'interactive_descendants.dart';

const _requestId = 'Brequest00001';
const _postId = 'Bparentpost01';
const _requestTitle = 'Bring a ladder';
const _author = Profile(id: 'Ualice', displayName: 'Alice');
const _viewer = Profile(id: 'Uviewer000001', displayName: 'Омар');
final _createdAt = DateTime.utc(2026, 10, 20, 12);
const _relatedText =
    'Вы видите этот запрос, потому что участвуете в связанном запросе.';
const _deadline = Duration(seconds: 5);

const _emptyHelpOffers = {
  '__typename': 'beacon_help_offer_aggregate',
  'aggregate': null,
};

Map<String, dynamic> _beaconRead({required bool isPost}) => {
  '__typename': 'query_root',
  'beacon_by_pk': {
    '__typename': 'beacon',
    'viewer_can_forward': true,
    'cover_source': 0,
    'needs': '',
    'created_at': _createdAt.toIso8601String(),
    'updated_at': _createdAt.toIso8601String(),
    'status': 0,
    'tags': '',
    'beacon_images': <Object>[],
    'help_offers_aggregate': _emptyHelpOffers,
    'unanswered_help_offers': _emptyHelpOffers,
    'admitted_helpers_aggregate': _emptyHelpOffers,
    'is_discoverable': true,
    'id': isPost ? _postId : _requestId,
    'title': isPost ? '' : _requestTitle,
    'description': '',
    'author': {
      '__typename': 'user',
      'id': _author.id,
      'display_name': _author.displayName,
      'description': '',
    },
    'kind': isPost ? 1 : 0,
    'forward_policy': 1,
    'post_draft_attachments': <Object>[],
    'active_help_offers': <Object>[],
    'participant_help_offers': <Object>[],
    'admitted_helpers': <Object>[],
    'can_read_content': true,
    'can_read_involvement': false,
    'access_level': BeaconAccessLevel.observer.value,
    'access_reasons': isPost ? 0 : BeaconAccessReason.contextChild.bit,
  },
};

const _postSummary = {
  '__typename': 'v2_PostSummary',
  'id': _postId,
  'authorId': 'Ualice',
  'authorName': 'Alice',
  'authorAvatar': '',
  'rootImageUrl': null,
  'rootExcerpt': 'Garden volunteers',
  'lastMessageExcerpt': null,
  'lastMessageIsRoot': true,
  'lastMessageAt': null,
  'lastActivityAt': '2026-10-24T12:00:00.000Z',
  'pinnedAt': null,
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'participantCount': 0,
  'notOpenedCount': 0,
  'myDeclinedForwardCount': 0,
  'previewParticipants': <Object>[],
  'isAuthor': false,
  'status': 0,
  'expiresAt': null,
};

Future<(BeaconViewCubit, List<WireSent>)> _loadRequest(
  WidgetTester tester,
) async {
  final sent = <WireSent>[];
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  late BeaconViewCubit cubit;
  await tester.runAsync(() async {
    await withRemoteWire(
      const {},
      sent,
      (remote) async {
        final repository = BeaconRepository(remote, realtime.port);
        cubit = BeaconViewCubit(
          id: _requestId,
          myProfile: _viewer,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: repository,
            realtimeSyncCase: realtime.case_,
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(() => tester.runAsync(repository.dispose));
        addTearDown(() => tester.runAsync(cubit.close));

        if (!cubit.state.beaconContextLoaded) {
          await cubit.stream
              .firstWhere((state) => state.beaconContextLoaded)
              .timeout(_deadline);
        }
        // Drain the background reads launched when Request content arrives.
        await pumpEventQueue();
      },
      responseFor: (call) async => switch (call.operationName) {
        'BeaconFetchById' => _beaconRead(
          isPost: call.variables['id'] == _postId,
        ),
        'BeaconParentReference' => {
          '__typename': 'query_root',
          'beaconParentReference': {
            '__typename': 'v2_BeaconParentReference',
            'state': 'available',
            'beaconId': _postId,
            'title': '',
            'isPost': true,
          },
        },
        'BeaconAdmittedHelpersRoster' || 'BeaconTeamAcquaintances' => {
          '__typename': 'query_root',
          'beacon_by_pk': {
            '__typename': 'beacon',
            'id': _requestId,
            'admitted_helpers': <Object>[],
          },
        },
        'PostSummary' => {
          '__typename': 'query_root',
          'postSummary': _postSummary,
        },
        _ => throw StateError(
          'Unexpected GraphQL operation: ${call.operationName}',
        ),
      },
    ).timeout(_deadline);
  });

  return (cubit, sent);
}

void main() {
  testWidgets(
    'an observer opens a Request without looking up its access parent',
    (
      tester,
    ) async {
      final (cubit, sent) = await _loadRequest(tester);

      expect(cubit.state.beacon.id, _requestId);
      expect(cubit.state.beacon.accessLevel, BeaconAccessLevel.observer);
      expect(
        cubit.state.beacon.accessReasons,
        BeaconAccessReason.contextChild.bit,
      );
      final host = beaconViewHarnessHost(beaconId: _requestId);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        final closing = host.close();
        await tester.pump();
        await closing;
        await unregisterBeaconViewHarnessGetIt();
      });
      await pumpBeaconViewHarness(
        tester,
        size: kPhoneSurface,
        locale: const Locale('ru'),
        beaconState: cubit.state,
        beaconViewCubit: cubit,
        threadsState: beaconViewHarnessThreadsState(authorId: _author.id),
        host: host,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BeaconViewScreen), findsOneWidget);
      expect(find.text(_requestTitle), findsWidgets);
      expect(find.byType(RequestAccessReasonBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      final reads = [
        for (final call in sent)
          if (const {
            'BeaconFetchById',
            'BeaconParentReference',
            'PostSummary',
          }.contains(call.operationName))
            (
              call.operationName,
              call.variables['id'] ?? call.variables['beaconId'],
            ),
      ];
      expect(
        [
          reads,
          find.text(_relatedText).evaluate().length,
          findInteractiveDescendants(
            find.byType(RequestAccessReasonBanner),
          ).evaluate().length,
        ],
        [
          [('BeaconFetchById', _requestId)],
          1,
          0,
        ],
        reason: 'the Request response alone provides the access explanation',
      );
    },
  );

  testWidgets(
    'the showcase and operational header explain related access from the Request alone',
    (tester) async {
      final (cubit, _) = await _loadRequest(tester);
      final host = beaconViewHarnessHost(beaconId: _requestId);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        final closing = host.close();
        await tester.pump();
        await closing;
        await unregisterBeaconViewHarnessGetIt();
      });
      await pumpBeaconViewHarness(
        tester,
        size: kPhoneSurface,
        locale: const Locale('ru'),
        beaconState: cubit.state,
        beaconViewCubit: cubit,
        threadsState: beaconViewHarnessThreadsState(authorId: _author.id),
        host: host,
      );
      await tester.pumpAndSettle();

      void expectReadableBanner(Type surface, String copy) {
        final text = find.descendant(
          of: find.byType(surface),
          matching: find.text(copy),
        );
        expect(text, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }

      expectReadableBanner(BeaconShowcaseSurface, _relatedText);
      final beacon = cubit.state.beacon;
      for (final (locale, copy) in [
        (const Locale('ru'), _relatedText),
        (
          const Locale('en'),
          'You can see this request because you take part in a related request.',
        ),
      ]) {
        for (final (level, reasons, shown) in [
          (BeaconAccessLevel.observer, 64, true),
          (BeaconAccessLevel.observer, 128, true),
          (BeaconAccessLevel.observer, 32 | 64, true),
          (BeaconAccessLevel.member, 64, false),
          (BeaconAccessLevel.author, 64, false),
          (null, 64, false),
          (BeaconAccessLevel.observer, 8, false),
          (BeaconAccessLevel.observer, 16 | 64, false),
        ]) {
          final state = cubit.state.copyWith(
            beacon: beacon.copyWith(accessLevel: level, accessReasons: reasons),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: TenturaResponsiveScope(
                child: Scaffold(
                  body: BeaconOperationalHeaderCard(
                    state: state,
                    onAuthorTap: () {},
                    showHudRows: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (shown) {
            expectReadableBanner(BeaconOperationalHeaderCard, copy);
          } else {
            expect(
              find.descendant(
                of: find.byType(RequestAccessReasonBanner),
                matching: find.byType(Text),
              ),
              findsNothing,
              reason: 'No access explanation for $level with reasons $reasons.',
            );
            expect(tester.takeException(), isNull);
          }
        }
      }

      const constructor = RequestAccessReasonBanner.new;
      final obsoleteInputs = <Symbol, Object>{
        #parent: beacon,
        const Symbol(
          'parentPost'
          'Excerpt',
        ): 'Unrelated Post',
      };
      for (final entry in obsoleteInputs.entries) {
        expect(
          () => Function.apply(
            constructor,
            [],
            {#beacon: beacon, entry.key: entry.value},
          ),
          throwsNoSuchMethodError,
          reason: 'The banner must reject the obsolete argument ${entry.key}.',
        );
      }
    },
  );

  test(
    'Request access callers and tests carry no parent data for the banner',
    () {
      const parentState =
          'access'
          'Parent';
      const postExcerpt =
          'parentPost'
          'Excerpt';
      const forbidden = [parentState, postExcerpt];
      final violations = <String>[];
      for (final directory in [Directory('lib'), Directory('test')]) {
        for (final file
            in directory.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          final source = file.readAsStringSync();
          for (final name in forbidden.where(source.contains)) {
            violations.add('${file.path} refers to $name');
          }
          if (!source.contains('RequestAccessReasonBanner') ||
              !source.contains('parent')) {
            continue;
          }

          final parsed = parseString(content: source, path: file.path);
          final calls = _BannerParentArguments();
          parsed.unit.accept(calls);
          for (final argument in calls.arguments) {
            final line = parsed.lineInfo
                .getLocation(argument.offset)
                .lineNumber;
            violations.add('${file.path}:$line passes parent to the banner');
          }
        }
      }
      expect(violations..sort(), isEmpty);
    },
  );
}

class _BannerParentArguments extends RecursiveAstVisitor<void> {
  final arguments = <NamedArgument>[];

  void _record(String name, ArgumentList argumentList) {
    if (name != 'RequestAccessReasonBanner') return;
    arguments.addAll(
      argumentList.arguments.whereType<NamedArgument>().where(
        (argument) => argument.name.lexeme == 'parent',
      ),
    );
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.type.name.lexeme, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node.methodName.name, node.argumentList);
    super.visitMethodInvocation(node);
  }
}
