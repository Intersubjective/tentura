import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

/// #605/#457: one shared group label/description lookup for every chip,
/// chip set and the routing mute screen.
void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    final l10n = lookupL10n(locale);

    test(
      'group labels are the localized group names (${locale.languageCode})',
      () {
        expect(
          CapabilityGroup.logistics.labelOf(l10n),
          l10n.capabilityGroupLogistics,
        );
        expect(
          CapabilityGroup.communication.labelOf(l10n),
          l10n.capabilityGroupCommunication,
        );
        expect(
          CapabilityGroup.knowledge.labelOf(l10n),
          l10n.capabilityGroupKnowledge,
        );
        expect(CapabilityGroup.care.labelOf(l10n), l10n.capabilityGroupCare);
        expect(
          CapabilityGroup.resources.labelOf(l10n),
          l10n.capabilityGroupResources,
        );
        expect(
          CapabilityGroup.technical.labelOf(l10n),
          l10n.capabilityGroupTechnical,
        );
        expect(CapabilityGroup.rpg.labelOf(l10n), l10n.capabilityGroupRpg);
        expect(
          CapabilityGroup.special.labelOf(l10n),
          l10n.capabilityGroupSpecial,
        );
      },
    );

    test('group descriptions are the localized descriptions '
        '(${locale.languageCode})', () {
      expect(
        CapabilityGroup.logistics.descriptionOf(l10n),
        l10n.capabilityGroupLogisticsDescription,
      );
      expect(
        CapabilityGroup.communication.descriptionOf(l10n),
        l10n.capabilityGroupCommunicationDescription,
      );
      expect(
        CapabilityGroup.knowledge.descriptionOf(l10n),
        l10n.capabilityGroupKnowledgeDescription,
      );
      expect(
        CapabilityGroup.care.descriptionOf(l10n),
        l10n.capabilityGroupCareDescription,
      );
      expect(
        CapabilityGroup.resources.descriptionOf(l10n),
        l10n.capabilityGroupResourcesDescription,
      );
      expect(
        CapabilityGroup.technical.descriptionOf(l10n),
        l10n.capabilityGroupTechnicalDescription,
      );
      expect(
        CapabilityGroup.rpg.descriptionOf(l10n),
        l10n.capabilityGroupRpgDescription,
      );
      expect(
        CapabilityGroup.special.descriptionOf(l10n),
        l10n.capabilityGroupSpecialDescription,
      );
    });

    test('every group has a distinct non-empty label and description '
        '(${locale.languageCode})', () {
      final labels = CapabilityGroup.values.map((g) => g.labelOf(l10n));
      final descriptions = CapabilityGroup.values.map(
        (g) => g.descriptionOf(l10n),
      );
      expect(labels.every((s) => s.isNotEmpty), isTrue);
      expect(descriptions.every((s) => s.isNotEmpty), isTrue);
      expect(labels.toSet(), hasLength(CapabilityGroup.values.length));
      expect(descriptions.toSet(), hasLength(CapabilityGroup.values.length));
    });
  }
}
