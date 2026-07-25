import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/features/capability/ui/widget/capability_tag_chip.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/features/capability/ui/widget/removable_capability_chips.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';

Widget _wrap(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('capability colour surfaces', () {
    testWidgets('BeaconRequirementsBar icons use group on-container colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const BeaconRequirementsBar(needs: {'transport', 'money'})),
      );
      await tester.pumpAndSettle();

      final transport = tester.widget<Icon>(
        find.byIcon(CapabilityTag.transport.icon),
      );
      final money = tester.widget<Icon>(find.byIcon(CapabilityTag.money.icon));
      expect(transport.size, 22);
      expect(money.size, 22);
      expect(
        transport.color,
        TenturaCapabilityColors.light.logistics.onContainer,
      );
      expect(
        money.color,
        TenturaCapabilityColors.light.resources.onContainer,
      );
    });

    testWidgets('CapabilityRequirementTags tint containers and keep icon size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CapabilityRequirementTags(
            tags: [CapabilityTag.transport],
            showHeading: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(
        find.byIcon(CapabilityTag.transport.icon),
      );
      expect(icon.size, 18);
      expect(
        icon.color,
        TenturaCapabilityColors.light.logistics.onContainer,
      );

      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(CapabilityRequirementTags),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(
        decoration.color,
        TenturaCapabilityColors.light.logistics.container,
      );
    });

    testWidgets('FilterChip uses group swatch without nesting a square glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              final l10n = L10n.of(context)!;
              return CapabilityTagFilterChip(
                tag: CapabilityTag.calls,
                l10n: l10n,
                theme: Theme.of(context),
                selected: false,
                isAutomatic: false,
                onSelected: (_) {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TenturaCapabilityGlyph), findsNothing);
      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(
        chip.backgroundColor,
        TenturaCapabilityColors.light.communication.container
            .withValues(alpha: 0.4),
      );
      final avatar = chip.avatar! as Icon;
      expect(avatar.size, 18);
      expect(
        avatar.color,
        TenturaCapabilityColors.light.communication.onContainer,
      );
    });

    testWidgets('ForwardCapabilityChips preserve 14 px icons and tint fill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const ForwardCapabilityChips(slugs: ['tools'])),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(CapabilityTag.tools.icon));
      expect(icon.size, 14);
      expect(
        icon.color,
        TenturaCapabilityColors.light.logistics.onContainer,
      );
      final chip = tester.widget<RawChip>(find.byType(RawChip));
      expect(
        chip.backgroundColor,
        TenturaCapabilityColors.light.logistics.container,
      );
    });

    testWidgets('RemovableCapabilityChips preserve 18 px icons and tint fill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RemovableCapabilityChips(
            slugs: const {'design'},
            onRemove: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(CapabilityTag.design.icon));
      expect(icon.size, 18);
      expect(
        icon.color,
        TenturaCapabilityColors.light.technical.onContainer,
      );
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(
        chip.backgroundColor,
        TenturaCapabilityColors.light.technical.container,
      );
    });

    test('coordination semantic colours are unchanged', () {
      final scheme = TenturaTheme.light().colorScheme;
      final tt = TenturaTokens.light;

      expect(
        coordinationStatusOnSurfaceColor(scheme, BeaconStatus.needsMoreHelp),
        scheme.error,
      );
      expect(
        coordinationStatusOnSurfaceColor(scheme, BeaconStatus.enoughHelp),
        scheme.tertiary,
      );
      expect(
        coordinationResponseInkColor(tt, CoordinationResponseType.useful),
        tt.good,
      );
      expect(
        coordinationResponseInkColor(tt, CoordinationResponseType.overlapping),
        tt.info,
      );
      expect(
        coordinationResponseInkColor(
          tt,
          CoordinationResponseType.needDifferentSkill,
        ),
        tt.warn,
      );
      expect(
        coordinationResponseInkColor(tt, CoordinationResponseType.notSuitable),
        tt.textMuted,
      );
    });
  });
}
