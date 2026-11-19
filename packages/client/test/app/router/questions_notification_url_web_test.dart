@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Questions notification links resolve to the same Request route and ID',
    () {
      final router = RootRouter(
        Logger('QuestionsNotificationUrlTest'),
        _Auth(),
        _Settings(),
        PostJoinNavigationCubit(),
      );
      addTearDown(router.dispose);

      final originalUrl = web.window.location.href;
      addTearDown(() => web.window.history.replaceState(null, '', originalUrl));

      const requestId = 'BquestionsURL01';
      for (final path in [
        '/beacon/questions/$requestId',
        '/beacon/lobby/$requestId',
      ]) {
        web.window.history.replaceState(null, '', '#$path');
        final browserPath = Uri.parse(web.window.location.href).fragment;
        expect(browserPath, path);
        final matches = router.matcher.match(browserPath);
        expect(matches, isNotEmpty, reason: path);
        final destination = matches!.last;
        expect(destination.name, BeaconLobbyRoute.name, reason: path);
        expect(destination.params.optString('id'), requestId, reason: path);
      }
    },
  );
}
