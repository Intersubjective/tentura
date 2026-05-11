import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/commitment_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', title: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit()),
      ],
      child: Scaffold(body: child),
    ),
  );
}

TimelineCommitment _commitment({
  required String userId,
  String? helpType,
  String message = '',
  bool isWithdrawn = false,
}) {
  final t = DateTime.utc(2025);
  return TimelineCommitment(
    user: Profile(id: userId, title: 'Committer'),
    message: message,
    createdAt: t,
    updatedAt: t,
    helpType: helpType,
    isWithdrawn: isWithdrawn,
  );
}

void main() {
  test('commitmentHelpTypeSlugs parses JSON array or single slug', () {
    expect(commitmentHelpTypeSlugs('["money","time"]'), ['money', 'time']);
    expect(commitmentHelpTypeSlugs('money'), ['money']);
    expect(commitmentHelpTypeSlugs('  '), isEmpty);
    expect(commitmentHelpTypeSlugs(null), isEmpty);
  });

  testWidgets('known help_type renders read-only RawChip with l10n label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CommitmentTile(
          commitment: _commitment(userId: 'c1', helpType: 'money'),
          beaconId: 'B1',
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(RawChip, 'Money'), findsOneWidget);
    final chip = tester.widget<RawChip>(
      find.widgetWithText(RawChip, 'Money'),
    );
    expect(chip.onPressed, isNull);
  });

  testWidgets('unknown help_type wire renders plain RawChip label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CommitmentTile(
          commitment: _commitment(userId: 'c1', helpType: 'legacy_unknown_key'),
          beaconId: 'B1',
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(
      find.widgetWithText(RawChip, 'legacy_unknown_key'),
      findsOneWidget,
    );
  });

  testWidgets('JSON-encoded help_type array renders one chip per slug', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CommitmentTile(
          commitment: _commitment(
            userId: 'c1',
            helpType: '["money","time"]',
          ),
          beaconId: 'B1',
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(RawChip, 'Money'), findsOneWidget);
    expect(find.widgetWithText(RawChip, 'Time'), findsOneWidget);
    expect(find.byType(RawChip), findsNWidgets(2));
  });

  testWidgets('null help_type hides capability row', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CommitmentTile(
          commitment: _commitment(userId: 'c1'),
          beaconId: 'B1',
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(RawChip), findsNothing);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('withdrawn commitment shows Withdrawn, not Active', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CommitmentTile(
          commitment: _commitment(userId: 'c1', isWithdrawn: true),
          beaconId: 'B1',
          beaconAuthorId: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets(
    'viewer commitment shows You in primary accent, no mine row',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          CommitmentTile(
            commitment: _commitment(userId: 'me'),
            beaconId: 'B1',
            beaconAuthorId: 'auth',
            isMine: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
      expect(find.text('mine'), findsNothing);
      final theme = Theme.of(tester.element(find.text('You')));
      final text = tester.widget<Text>(find.text('You'));
      expect(text.style?.color, theme.colorScheme.primary);
      expect(text.style?.fontWeight, FontWeight.w600);
    },
  );
}
