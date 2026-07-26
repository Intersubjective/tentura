import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  Uri? launchedUri;
  Uri? launchedUserLink;

  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {
    launchedUri = uri;
  }

  @override
  Future<void> launchUrl(String uri) async {
    launchedUri = Uri.parse(uri);
  }

  @override
  Future<void> launchUserLink(Uri uri) async {
    launchedUserLink = uri;
  }
}

MyWorkCardViewModel _viewModel(Beacon beacon) => MyWorkCardViewModel(
  beaconId: beacon.id,
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: beacon,
);

Widget _metadataHarness(Widget child) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 800)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _FakePlatformRepository platform;

  setUp(() async {
    await GetIt.I.reset();
    platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('compact strip location opens actions and launches Maps URI', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b-location',
      author: const Profile(id: 'a1', displayName: 'Alice'),
      coordinates: const Coordinates(lat: 52.358, long: 4.881),
      addressLabel: 'Museumplein 6, Amsterdam',
      createdAt: DateTime(2026, 6, 10, 9),
      updatedAt: DateTime(2026, 6, 10, 10),
    );

    await tester.pumpWidget(
      _metadataHarness(
        MyWorkCardMetadataRow(
          beacon: beacon,
          viewModel: _viewModel(beacon),
          currentUserId: 'viewer',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Museumplein 6, Amsterdam'));
    await tester.pumpAndSettle();

    expect(find.text('Open in Maps'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Copy coordinates'), findsOneWidget);

    await tester.tap(find.text('Open in Maps'));
    await tester.pumpAndSettle();

    expect(
      platform.launchedUri.toString(),
      'geo:52.358,4.881?q=52.358,4.881(Museumplein%206%2C%20Amsterdam)',
    );
  });

  testWidgets('compact strip location tap does not trigger card onTap', (
    tester,
  ) async {
    var cardTapped = false;
    final beacon = Beacon.empty.copyWith(
      id: 'b-location',
      author: const Profile(id: 'a1', displayName: 'Alice'),
      coordinates: const Coordinates(lat: 52.358, long: 4.881),
      addressLabel: 'Museumplein 6, Amsterdam',
      createdAt: DateTime(2026, 6, 10, 9),
      updatedAt: DateTime(2026, 6, 10, 10),
    );

    await tester.pumpWidget(
      _metadataHarness(
        BeaconCardShell(
          onTap: () => cardTapped = true,
          child: MyWorkCardMetadataRow(
            beacon: beacon,
            viewModel: _viewModel(beacon),
            currentUserId: 'viewer',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Museumplein 6, Amsterdam'));
    await tester.pumpAndSettle();

    expect(find.text('Open in Maps'), findsOneWidget);
    expect(cardTapped, isFalse);
  });
}
