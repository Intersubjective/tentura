// A newcomer inherits the viewer's tag that holds their inviter: Anna has
// Boris in her tag «T», Boris invited Nova, and when Nova first shows up on
// Anna's Field the server puts Nova into «T» marked as inherited (source 4).
// On Nova's profile Anna must then see «T» under «Ваши теги» with the ✦
// marker, who set it, and the Keep action; Keep and × act on that
// membership.
//
// These tests run the real read path: the `PersonTags`,
// `PersonTagMemberships` and `PersonTagMembersApply` responses travel through
// the real Ferry link chain (only HTTP is faked), the real
// `PeopleTagsRepository` mapper and the real `PeopleTagsCase` store into the
// profile's `PersonTagsBlock`, on an iPhone SE surface in Russian.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/person_tags_block.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

const _boris = 'Uboris0000001';
const _nova = 'Unova00000001';
const _tagT = 'Ttag000000001';
const _tagName = 'Мастерская';
const _borisRu = 'Борис';

final _inheritedSparkle = find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains('✦'),
);

Finder get _chipT => find.widgetWithText(PersonTagChip, _tagName);

/// Anna's tag state as the server holds it.
final class _AnnaTagsOnServer {
  _AnnaTagsOnServer({required this.novaInherited});

  /// Nova sits in «T» as an inherited member (source 4).
  bool novaInherited;

  /// Nova sits in «T» as an ordinary member.
  bool novaKept = false;

  final applied = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> respond(WireSent request) async {
    switch (request.operationName) {
      case 'PersonTags':
        return {
          '__typename': 'query_root',
          'personTags': [
            {
              '__typename': 'v2_PersonTag',
              'id': _tagT,
              'name': _tagName,
              'glyph': 'М',
              'color': 2,
              'ord': 0,
              'count': novaInherited || novaKept ? 2 : 1,
              'countOffField': 0,
            },
          ],
        };
      case 'PersonTagMemberships':
        return {
          '__typename': 'query_root',
          'personTagMemberships': [
            {
              '__typename': 'v2_PersonTagMembers',
              'tagId': _tagT,
              'personIds': [_boris, if (novaInherited || novaKept) _nova],
              'inherited': [
                if (novaInherited)
                  {
                    '__typename': 'v2_PersonTagInherited',
                    'personId': _nova,
                    'inviterId': _boris,
                  },
              ],
            },
          ],
        };
      case 'PersonTagsOf':
        return {
          '__typename': 'query_root',
          'personTagsOf': {
            '__typename': 'v2_PersonTagsOf',
            'own': [if (novaInherited || novaKept) _tagT],
            'auto': <Object>[],
          },
        };
      case 'PersonTagMembersApply':
        final ops = (request.variables['ops']! as List)
            .cast<Map<String, dynamic>>();
        applied.addAll(ops);
        for (final op in ops) {
          if (op['personId'] != _nova || op['tagId'] != _tagT) continue;
          switch (op['op']) {
            case 'keep':
              novaKept = novaInherited || novaKept;
              novaInherited = false;
            case 'remove':
              novaKept = false;
              novaInherited = false;
          }
        }
        return {'__typename': 'mutation_root', 'personTagMembersApply': true};
    }
    throw StateError('unexpected operation ${request.operationName}');
  }
}

final class _ProfilesRu implements ProfileRepositoryPort {
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    if (ids.contains(_boris)) const Profile(id: _boris, displayName: _borisRu),
    if (ids.contains(_nova)) const Profile(id: _nova, displayName: 'Нова'),
  ];

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Pumps with real waits until [done] holds (wire answers and the store's
/// debounce run on real time).
Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Nova's profile tag block for Anna, over the real repository and store.
Future<void> _withNovaProfile(
  WidgetTester tester,
  _AnnaTagsOnServer server,
  List<WireSent> sent,
  Future<void> Function(TestRealtimeSyncPort realtime) body,
) async {
  await usePhoneSurface(tester);
  await tester.runAsync(() async {
    await withRemoteWire(
      const {},
      sent,
      responseFor: server.respond,
      (remote) async {
        final realtime = buildTestRealtimeSync();
        final peopleTags = PeopleTagsCase(
          PeopleTagsRepository(remote),
          realtime.case_,
          env: const Env(),
          logger: Logger('person-tags-block-inherited-wire'),
        );
        final profiles = _ProfilesRu();
        GetIt.I
          ..registerSingleton<PeopleTagsCase>(peopleTags)
          ..registerSingleton<ProfileRepositoryPort>(profiles);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: const Locale('ru'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: const TenturaResponsiveScope(
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: PersonTagsBlock(personId: _nova),
                  ),
                ),
              ),
            ),
          );
          await _settleUntil(tester, () => peopleTags.hasLoaded);
          await body(realtime.port);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          await GetIt.I.reset();
          await peopleTags.dispose();
          await realtime.port.dispose();
          await profiles.dispose();
        }
      },
    );
  });
}

void main() {
  final ru = lookupL10n(const Locale('ru'));

  group("a newcomer's inherited tag on their profile, from the server's "
      'memberships, at phone width in Russian', () {
    testWidgets('shows the tag under «Ваши теги» with ✦, who set it, and '
        '«Оставить», without overflow', (tester) async {
      final semantics = tester.ensureSemantics();
      final server = _AnnaTagsOnServer(novaInherited: true);
      final sent = <WireSent>[];

      await _withNovaProfile(tester, server, sent, (_) async {
        await _settleUntil(tester, () => _chipT.evaluate().isNotEmpty);

        expect(
          sent.map((r) => r.operationName),
          contains('PersonTagMemberships'),
        );
        expect(find.text(ru.peopleTagsYourTags), findsOneWidget);
        expect(_chipT, findsOneWidget);
        expect(_inheritedSparkle, findsOneWidget);
        expect(
          find.bySemanticsLabel(ru.peopleTagsInheritedChipSemantics(_borisRu)),
          findsOneWidget,
        );
        expect(
          find.text('Поставлено автоматически: пригласил(а) $_borisRu'),
          findsNothing,
          reason: 'the inviter line is for screen readers and the tooltip',
        );
        expect(find.text(ru.peopleTagsInheritedKeep), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      semantics.dispose();
    });

    testWidgets('shows the tag once the store, loaded before the Field read '
        'that inherited it, hears that the tags changed', (tester) async {
      final server = _AnnaTagsOnServer(novaInherited: false);
      final sent = <WireSent>[];

      await _withNovaProfile(tester, server, sent, (realtime) async {
        expect(_chipT, findsNothing);
        expect(find.text(ru.constellationTagRowAdd), findsOneWidget);

        // Anna's Field read meets Nova live and the server copies «T».
        server.novaInherited = true;
        realtime.emitChange(
          RealtimeEntityChange(
            kind: RealtimeEntityKind.personTag,
            aggregateId: 'Uviewer000001',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
            revision: BigInt.from(7),
          ),
        );
        await _settleUntil(tester, () => _chipT.evaluate().isNotEmpty);

        expect(_chipT, findsOneWidget);
        expect(_inheritedSparkle, findsOneWidget);
        expect(find.text(ru.peopleTagsInheritedKeep), findsOneWidget);
      });
    });

    testWidgets('«Оставить» keeps Nova in the tag and drops the ✦ marker', (
      tester,
    ) async {
      final server = _AnnaTagsOnServer(novaInherited: true);
      final sent = <WireSent>[];

      await _withNovaProfile(tester, server, sent, (_) async {
        await _settleUntil(tester, () => _chipT.evaluate().isNotEmpty);
        expect(_inheritedSparkle, findsOneWidget);

        await tester.tap(find.text(ru.peopleTagsInheritedKeep));
        await _settleUntil(tester, () => server.applied.isNotEmpty);

        expect(server.applied, [
          {'tagId': _tagT, 'personId': _nova, 'op': 'keep', 'source': 0},
        ]);
        expect(_inheritedSparkle, findsNothing);
        expect(_chipT, findsOneWidget);
        expect(find.text(ru.peopleTagsInheritedKeep), findsNothing);
      });
    });

    testWidgets('× takes Nova out of the tag and says so', (tester) async {
      final server = _AnnaTagsOnServer(novaInherited: true);
      final sent = <WireSent>[];

      await _withNovaProfile(tester, server, sent, (_) async {
        await _settleUntil(tester, () => _chipT.evaluate().isNotEmpty);

        await tester.tap(
          find.descendant(of: _chipT, matching: find.byIcon(Icons.close)),
        );
        await _settleUntil(
          tester,
          () => find
              .text(ru.peopleTagsRemovedFromPersonOnPeer(_tagName))
              .evaluate()
              .isNotEmpty,
        );

        expect(
          server.applied.map((op) => (op['tagId'], op['personId'], op['op'])),
          [(_tagT, _nova, 'remove')],
        );
        expect(_chipT, findsNothing);
        expect(find.text('Тег «Мастерская» убран'), findsOneWidget);
      });
    });
  });
}
