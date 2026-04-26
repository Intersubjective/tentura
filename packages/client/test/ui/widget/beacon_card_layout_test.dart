import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('compact header uses 40px identity and title max two lines at 360px', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025, 4, 18, 17, 6),
      id: 'b1',
      title:
          '"Sweet spot": разгребаем завалы и длинный хвост чтобы title занял две строки',
      context: 'General',
      author: const Profile(id: 'a1', title: 'Fionna Campbell'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BeaconCardShell(
                  child: BeaconCardHeaderRow(
                    beacon: beacon,
                    menu: const SizedBox(
                      width: 32,
                      height: 40,
                      child: Placeholder(),
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

    final box = tester.getSize(find.byType(BeaconIdentityTile));
    expect(box.width, 40);
    expect(box.height, 40);

    final titleFinder = find.textContaining('"Sweet spot"', findRichText: true);
    expect(titleFinder, findsOneWidget);
    final renderObject = tester.renderObject<RenderParagraph>(titleFinder);
    expect(renderObject.size.height <= 50, isTrue);
  });

  testWidgets('metadata block aligns updated line with author name column', (
    tester,
  ) async {
    const name = 'Fionna Campbell';
    const category = 'General';
    const updatedLine = 'Updated 2025-04-18 17:06';

    final profileCubit = _TestProfileCubit();

    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: profileCubit,
        child: MaterialApp(
          theme: TenturaTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(360, 800)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: BeaconCardMetadataBlock(
                    author: Profile(id: 'a1', title: name),
                    name: name,
                    nameStyle: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    baseStyle: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: FontWeight.w400,
                    ),
                    category: category,
                    updatedLine: updatedLine,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameFinder = find.textContaining(name, findRichText: true);
    expect(nameFinder, findsOneWidget);
    final updatedFinder = find.text(updatedLine);
    expect(updatedFinder, findsOneWidget);

    final nameLeft = tester.getRect(nameFinder).left;
    final updatedLeft = tester.getRect(updatedFinder).left;
    expect(
      (nameLeft - updatedLeft).abs() < 0.01,
      isTrue,
      reason: 'author and updated should share the same left edge',
    );
  });
}
