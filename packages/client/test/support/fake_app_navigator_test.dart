import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/navigation/app_navigator.dart';

import 'fake_app_navigator.dart';

void main() {
  testWidgets(
    'registering a fresh fake navigator replaces the previous fake and '
    'records subsequent navigation separately',
    (tester) async {
      final getIt = GetIt.I..pushNewScope();
      addTearDown(getIt.popScope);

      final first = registerFakeAppNavigator();
      expect(getIt<AppNavigator>(), same(first));
      await getIt<AppNavigator>().openProfile('first-profile');
      expect(first.intents, [
        const NavIntent('openProfile', {'id': 'first-profile'}),
      ]);

      final replacement = registerFakeAppNavigator();

      expect(replacement, isNot(same(first)));
      expect(getIt<AppNavigator>(), same(replacement));
      expect(replacement.intents, isEmpty);
      await getIt<AppNavigator>().openProfile('second-profile');
      expect(replacement.intents, [
        const NavIntent('openProfile', {'id': 'second-profile'}),
      ]);
      expect(first.intents, [
        const NavIntent('openProfile', {'id': 'first-profile'}),
      ]);
    },
  );
}
