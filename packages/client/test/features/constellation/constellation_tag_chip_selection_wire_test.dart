import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

Map<String, dynamic> _tagWire(PersonTag tag) => {
  '__typename': 'PersonTag',
  'id': tag.id,
  'name': tag.name,
  'glyph': tag.glyph,
  'color': tag.color,
  'ord': tag.ord,
  'count': 0,
  'countOffField': 0,
};

const _wireTag = PersonTag(
  id: 'wire-tag',
  name: 'Wire neighbour',
  glyph: 'W',
  color: 2,
  ord: 0,
);

void main() {
  testWidgets('375×667 RU: wire-loaded tag row shows check when selected', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final sent = <WireSent>[];
    late List<PersonTag> tags;
    await withRemoteWire(
      {
        'PersonTags': {
          '__typename': 'query_root',
          'personTags': [_tagWire(_wireTag)],
        },
        'PersonTagMemberships': {
          '__typename': 'query_root',
          'personTagMemberships': <Map<String, dynamic>>[],
        },
      },
      sent,
      (remote) async {
        final sync = buildTestRealtimeSync();
        addTearDown(() async => sync.port.dispose());
        final peopleTags = PeopleTagsCase(
          PeopleTagsRepository(remote),
          sync.case_,
          env: const Env(),
          logger: Logger('ConstellationTagChipSelectionWireTest'),
        );
        addTearDown(() async => peopleTags.dispose());
        await peopleTags.load();
        tags = peopleTags.tags;
      },
    );
    expect(tags, isNotEmpty);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ConstellationTagRow(
            ownTags: tags,
            autoTags: const [],
            filter: const ConstellationTagFilter(selectedOwn: {'wire-tag'}),
            onToggleOwn: (_) {},
            onToggleAuto: (_) {},
            onModeChanged: (_) {},
            onAddTag: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wire neighbour'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PersonTagChip),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(sent.map((s) => s.operationName), contains('PersonTags'));
  });
}
