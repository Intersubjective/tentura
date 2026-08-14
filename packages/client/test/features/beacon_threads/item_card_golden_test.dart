import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/widget/item_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _GoldenProfileCubit extends Mock implements ProfileCubit {
  _GoldenProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

const _kBeaconId = 'B-golden';
const _kAuthorId = 'author-g';
const _kOtherId = 'other-g';
final _kAt = DateTime.utc(2026, 8, 14, 9, 15);

CoordinationItem _askItem() => CoordinationItem(
  id: 'ask-golden',
  beaconId: _kBeaconId,
  kind: CoordinationItemKind.ask,
  status: CoordinationItemStatus.open,
  creatorId: _kAuthorId,
  targetPersonId: _kOtherId,
  createdAt: _kAt,
  updatedAt: _kAt,
  title: 'Code review',
  body:
      'Can you review the migration script before Friday? '
      'Focus on the thread preview mapper and the watermark store changes '
      'so we can ship the boxed list without nested scroll views.',
  published: true,
  messageCount: 6,
  unreadCount: 2,
);

RequestThread _generalThread() => RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  messageCount: 12,
  unreadCount: 1,
  lastMessageAt: _kAt.subtract(const Duration(minutes: 18)),
  lastMessageAuthorId: _kOtherId,
  lastMessagePreview: const ThreadMessagePreview(
    kind: ThreadMessagePreviewKind.text,
    excerpt: 'Thanks — I pushed the latest fixes to the branch.',
  ),
);

RequestThread _semanticThread(CoordinationItem item) => RequestThread(
  threadId: item.id,
  kind: RequestThreadKind.ask,
  messageCount: item.messageCount,
  unreadCount: item.unreadCount,
  item: item,
  lastMessageAt: _kAt.subtract(const Duration(hours: 2)),
  lastMessageAuthorId: _kOtherId,
  lastMessagePreview: const ThreadMessagePreview(
    kind: ThreadMessagePreviewKind.text,
    excerpt: 'I can take a look tonight after standup.',
  ),
);

List<BeaconParticipant> _participants() => [
  BeaconParticipant(
    id: 'p-author',
    beaconId: _kBeaconId,
    userId: _kAuthorId,
    userTitle: 'Alex Author',
    handle: 'alex',
    role: 0,
    status: 0,
    roomAccess: 1,
    createdAt: _kAt,
    updatedAt: _kAt,
  ),
  BeaconParticipant(
    id: 'p-other',
    beaconId: _kBeaconId,
    userId: _kOtherId,
    userTitle: 'Sam Helper',
    handle: 'sam',
    role: 0,
    status: 0,
    roomAccess: 1,
    createdAt: _kAt,
    updatedAt: _kAt,
  ),
];

Future<void> _pumpGolden(
  WidgetTester tester, {
  required ThemeData theme,
  required bool expandSemantic,
}) async {
  final viewer = const Profile(id: _kAuthorId, displayName: 'Alex Author');
  final participants = _participants();
  final item = _askItem();

  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _GoldenProfileCubit(viewer),
      child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 520)),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ItemCard(
                        thread: _generalThread(),
                        viewerProfile: viewer,
                        participants: participants,
                        resolvedUnreadCount: 1,
                        onOpenThread: (_) {},
                      ),
                      const SizedBox(height: 10),
                      ItemCard(
                        key: const Key('semantic-card'),
                        thread: _semanticThread(item),
                        viewerProfile: viewer,
                        participants: participants,
                        resolvedUnreadCount: 2,
                        creatorParticipant: participants.first,
                        targetParticipant: participants.last,
                        onOpenThread: (_) {},
                        onResolve: () {},
                        onCancel: () {},
                        onAccept: () {},
                        onEdit: () {},
                        onRemind: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    ),
  );
  await tester.pumpAndSettle();
  if (expandSemantic) {
    await tester.tap(find.text('show more'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('ItemCard golden collapsed light', (tester) async {
    await _pumpGolden(tester, theme: TenturaTheme.light(), expandSemantic: false);
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/item_card_collapsed_light.png'),
    );
  });

  testWidgets('ItemCard golden collapsed dark', (tester) async {
    await _pumpGolden(tester, theme: TenturaTheme.dark(), expandSemantic: false);
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/item_card_collapsed_dark.png'),
    );
  });

  testWidgets('ItemCard golden expanded light', (tester) async {
    await _pumpGolden(tester, theme: TenturaTheme.light(), expandSemantic: true);
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/item_card_expanded_light.png'),
    );
  });

  testWidgets('ItemCard golden expanded dark', (tester) async {
    await _pumpGolden(tester, theme: TenturaTheme.dark(), expandSemantic: true);
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/item_card_expanded_dark.png'),
    );
  });
}
