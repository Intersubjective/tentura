import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/plain_mini_avatar.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

void main() {
  testWidgets('PlainMiniAvatar shows asset placeholder when profile has no photo', (
    tester,
  ) async {
    const profile = Profile(id: 'user-1', displayName: 'No Photo User');

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: Center(
            child: PlainMiniAvatar(profile: profile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(profile.hasNoAvatar, isTrue);
    expect(tester.getSize(find.byType(PlainMiniAvatar)).width, AvatarRated.sizeSmall);

    final image = tester.widget<Image>(find.byType(Image));
    var provider = image.image;
    if (provider is ResizeImage) {
      provider = provider.imageProvider;
    }
    expect(provider, isA<AssetImage>());
    expect((provider as AssetImage).assetName, contains('avatar.jpg'));
  });
}
