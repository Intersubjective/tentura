import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
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

const _shortWireTag = PersonTag(
  id: 'wire-short',
  name: 'Тег',
  glyph: 'T',
  color: 1,
  ord: 0,
);

void main() {
  testWidgets('375×667 RU: wire-loaded sheet wrap chips hug content width', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final sent = <WireSent>[];
    late List<PersonTag> tags;
    await withRemoteWire(
      {
        'PersonTags': {
          '__typename': 'query_root',
          'personTags': [_tagWire(_shortWireTag)],
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
          logger: Logger('ConstellationAllTagsSheetWireTest'),
        );
        addTearDown(() async => peopleTags.dispose());
        await peopleTags.load();
        tags = peopleTags.tags;
      },
    );
    expect(tags, isNotEmpty);

    final lens = ConstellationTagLensCubit();
    addTearDown(lens.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: BlocProvider.value(
          value: lens,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showConstellationAllTagsSheet(
                  context: context,
                  lensCubit: lens,
                  ownTags: tags,
                  autoTags: const [],
                  onAddTag: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final tt = TenturaTheme.light().extension<TenturaTokens>()!;
    final maxLine = kPhoneSurface.width - 2 * tt.screenHPadding;
    final chipSize = tester.getSize(
      find.ancestor(
        of: find.text('Тег'),
        matching: find.byType(PersonTagChip),
      ),
    );
    expect(chipSize.width, lessThan(maxLine * 0.45));
    expect(sent.map((s) => s.operationName), contains('PersonTags'));
    expect(tester.takeException(), isNull);
  });
}
