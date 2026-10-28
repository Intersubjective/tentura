@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _longExcerpt =
    'Anyone free on Saturday morning to help carry the old piano down '
    'three flights of stairs, then across the courtyard and into the van '
    'that is waiting in the back lane behind the bakery?';

ConstellationField _fieldWithPosts(Map<String, String> excerptByPostId) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 28),
      context: '',
      peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
      edges: [
        const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
      ],
      posts: [
        for (final entry in excerptByPostId.entries)
          ConstellationPost(
            id: entry.key,
            authorId: 'a',
            rootExcerpt: entry.value,
            lastActivityAt: DateTime.utc(2026, 10, 28),
          ),
      ],
    );

void main() {
  group('Constellation post labels at the closest detail level', () {
    Future<ConstellationPresentationFrame> mountClose(
      WidgetTester tester,
      Map<String, String> excerptByPostId,
    ) async {
      final cubit = await loadReferenceCubit(
        field: _fieldWithPosts(excerptByPostId),
      );
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        locale: const Locale('en'),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();
      cubit.graphController.zoomBy(
        1.0 / cubit.graphController.cameraScale,
      );
      await tester.pumpAndSettle();
      expect(holder.frame!.detail, ConstellationDetailLevel.close);
      return holder.frame!;
    }

    testWidgets('give a post with an excerpt a label rect with room to spare', (
      tester,
    ) async {
      final frame = await mountClose(tester, {'post-long': _longExcerpt});

      // The author's own name is labelled, so the Field has room for labels.
      expect(frame.labels, contains('fp:a'));
      final rect = frame.labels['fr:post-long'];
      expect(rect, isNotNull, reason: 'a post with an excerpt is labelled');
      expect(rect!.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });

    testWidgets('show the start of the excerpt, cut off with an ellipsis', (
      tester,
    ) async {
      await mountClose(tester, {'post-long': _longExcerpt});

      final plate = find.byKey(
        const ValueKey('constellation.label.fr:post-long'),
      );
      expect(plate, findsOneWidget);
      final text = find.descendant(of: plate, matching: find.byType(Text));
      expect(text, findsOneWidget);
      final widget = tester.widget<Text>(text);
      expect(widget.data, startsWith('Anyone free on Saturday'));
      expect(widget.overflow, TextOverflow.ellipsis);
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isTrue,
        reason: 'a long excerpt does not fit the plate whole',
      );
    });

    testWidgets('label each post with its own excerpt text', (tester) async {
      const shortExcerpt = 'Lend me a ladder';
      const otherLongExcerpt =
          'Looking for a calm evening to practise Spanish over tea with '
          'someone patient, nothing formal, beginners very welcome here';
      await mountClose(tester, {
        'post-short': shortExcerpt,
        'post-other': otherLongExcerpt,
      });

      Text labelOf(String postId) {
        final plate = find.byKey(ValueKey('constellation.label.fr:$postId'));
        expect(plate, findsOneWidget);
        return tester.widget<Text>(
          find.descendant(of: plate, matching: find.byType(Text)),
        );
      }

      expect(labelOf('post-short').data, shortExcerpt);
      expect(labelOf('post-other').data, startsWith('Looking for a calm'));
      expect(labelOf('post-other').overflow, TextOverflow.ellipsis);
    });

    testWidgets('give a post with an empty excerpt no label', (tester) async {
      final frame = await mountClose(tester, {
        'post-long': _longExcerpt,
        'post-empty': '',
      });

      // Positive control: the post next to it is labelled.
      expect(frame.labels, contains('fr:post-long'));
      expect(frame.labels, isNot(contains('fr:post-empty')));
      expect(
        find.byKey(const ValueKey('constellation.label.fr:post-empty')),
        findsNothing,
      );
    });
  });
}
