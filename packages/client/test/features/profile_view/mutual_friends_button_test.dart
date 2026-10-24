import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile_view/data/repository/mutual_friends_repository.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _rawError = 'GraphQL error: permission check failed on mutual_friends';

final class _FailingMutualFriendsRepository implements MutualFriendsRepository {
  @override
  Future<List<Profile>> fetchMutualFriends(String userId) async =>
      throw Exception(_rawError);
}

/// #495 review: a failed mutual-friends load shows a friendly error bar, not
/// the raw exception text.
void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<Logger>(Logger('mutual-friends-test'))
      ..registerSingleton<MutualFriendsRepository>(
        _FailingMutualFriendsRepository(),
      );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  for (final language in const ['en', 'ru']) {
    testWidgets('a failed load shows the friendly error, not the raw '
        'exception ($language)', (tester) async {
      late L10n l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                l10n = L10n.of(context)!;
                return const MutualFriendsButton(userId: 'u1');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text(l10n.showMutualFriends));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining(l10n.errorGenericAction, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(_rawError, findRichText: true),
        findsNothing,
      );
    });
  }
}
