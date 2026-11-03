import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

void main() {
  testWidgets('375×667 RU: ellipsize keeps a second line for Post lifetime', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(375, 667)),
          child: TenturaResponsiveScope(
            child: Builder(
              builder: (context) {
                final tt = context.tt;
                final style = TenturaText.labelSmall(
                  Theme.of(context).colorScheme.onSurface,
                );
                final excerpt = ellipsizeConstellationLabelLine(
                  'Anyone free on Saturday morning to help carry the old piano down '
                  'three flights of stairs, then across the courtyard and into the van '
                  'that is waiting in the back lane behind the bakery?',
                  style: style,
                  maxWidth: tt.graphLabelMaxWidthRequest - 2 * tt.iconTextGap,
                  textScaler: MediaQuery.textScalerOf(context),
                  direction: Directionality.of(context),
                );
                const lifetime = '⏳ осталось 2 д';
                final label = '$excerpt\n$lifetime';
                return Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  key: const Key('sample'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final text = tester.widget<Text>(find.byKey(const Key('sample')));
    expect(text.data, contains('\n⏳ осталось 2 д'));
    expect(text.maxLines, 2);
  });
}
