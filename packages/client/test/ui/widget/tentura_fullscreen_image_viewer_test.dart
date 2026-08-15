import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';

void main() {
  testWidgets('shows InteractiveViewer and network image for one gallery item',
      (tester) async {
    const image = TenturaGalleryImage(
      url: 'https://example.com/avatar.jpg',
      blurHash: 'L6PZfSi_.AyE_3t7t7R**0o#DgR4',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const TenturaFullscreenImageViewer(
          images: [image],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('scaffold uses theme bg in dark mode', (tester) async {
    const image = TenturaGalleryImage(
      url: 'https://example.com/avatar.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.dark(),
        home: const TenturaFullscreenImageViewer(
          images: [image],
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, TenturaPalette.bgDark);
  });

  testWidgets('openProfileAvatarFullscreen pushes viewer when profile has avatar',
      (tester) async {
    const profile = Profile(
      id: 'user-1',
      image: ImageEntity(id: 'img-1'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openProfileAvatarFullscreen(context, profile),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(TenturaFullscreenImageViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('openProfileAvatarFullscreen is no-op when profile has no avatar',
      (tester) async {
    const profile = Profile();

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openProfileAvatarFullscreen(context, profile),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(TenturaFullscreenImageViewer), findsNothing);
  });
}
