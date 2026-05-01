import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// A grouped, selectable chip set for capability tags.
///
/// [selectedSlugs] is the current selection; [onChanged] fires on every toggle.
class CapabilityChipSet extends StatelessWidget {
  const CapabilityChipSet({
    required this.selectedSlugs,
    required this.onChanged,
    super.key,
  });

  final Set<String> selectedSlugs;
  final void Function(Set<String> slugs) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final group in CapabilityGroup.values)
          _GroupSection(
            group: group,
            groupLabel: _groupLabel(l10n, group),
            tags: CapabilityTag.values
                .where((t) => t.group == group)
                .toList(),
            selectedSlugs: selectedSlugs,
            onToggle: (slug, selected) {
              final next = Set<String>.from(selectedSlugs);
              selected ? next.add(slug) : next.remove(slug);
              onChanged(next);
            },
            theme: theme,
            l10n: l10n,
          ),
      ],
    );
  }

  static String _groupLabel(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogistics,
        CapabilityGroup.communication => l10n.capabilityGroupCommunication,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledge,
        CapabilityGroup.care => l10n.capabilityGroupCare,
        CapabilityGroup.resources => l10n.capabilityGroupResources,
        CapabilityGroup.technical => l10n.capabilityGroupTechnical,
        CapabilityGroup.special => l10n.capabilityGroupSpecial,
      };
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.groupLabel,
    required this.tags,
    required this.selectedSlugs,
    required this.onToggle,
    required this.theme,
    required this.l10n,
  });

  final CapabilityGroup group;
  final String groupLabel;
  final List<CapabilityTag> tags;
  final Set<String> selectedSlugs;
  final void Function(String slug, bool selected) onToggle;
  final ThemeData theme;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            groupLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final tag in tags)
              FilterChip(
                label: Text(_tagLabel(l10n, tag)),
                selected: selectedSlugs.contains(tag.slug),
                onSelected: (v) => onToggle(tag.slug, v),
              ),
          ],
        ),
      ],
    );
  }

  static String _tagLabel(L10n l10n, CapabilityTag tag) => switch (tag) {
    CapabilityTag.transport => l10n.capabilityTagTransport,
    CapabilityTag.storage => l10n.capabilityTagStorage,
    CapabilityTag.pickupDelivery => l10n.capabilityTagPickupDelivery,
    CapabilityTag.tools => l10n.capabilityTagTools,
    CapabilityTag.physicalHelp => l10n.capabilityTagPhysicalHelp,
    CapabilityTag.calls => l10n.capabilityTagCalls,
    CapabilityTag.translation => l10n.capabilityTagTranslation,
    CapabilityTag.writing => l10n.capabilityTagWriting,
    CapabilityTag.negotiation => l10n.capabilityTagNegotiation,
    CapabilityTag.introductions => l10n.capabilityTagIntroductions,
    CapabilityTag.localKnowledge => l10n.capabilityTagLocalKnowledge,
    CapabilityTag.legalNavigation => l10n.capabilityTagLegalNavigation,
    CapabilityTag.medicalNavigation => l10n.capabilityTagMedicalNavigation,
    CapabilityTag.documents => l10n.capabilityTagDocuments,
    CapabilityTag.verification => l10n.capabilityTagVerification,
    CapabilityTag.pets => l10n.capabilityTagPets,
    CapabilityTag.childcare => l10n.capabilityTagChildcare,
    CapabilityTag.eldercare => l10n.capabilityTagEldercare,
    CapabilityTag.emotionalSupport => l10n.capabilityTagEmotionalSupport,
    CapabilityTag.hosting => l10n.capabilityTagHosting,
    CapabilityTag.money => l10n.capabilityTagMoney,
    CapabilityTag.food => l10n.capabilityTagFood,
    CapabilityTag.housing => l10n.capabilityTagHousing,
    CapabilityTag.equipment => l10n.capabilityTagEquipment,
    CapabilityTag.workspace => l10n.capabilityTagWorkspace,
    CapabilityTag.techHelp => l10n.capabilityTagTechHelp,
    CapabilityTag.repair => l10n.capabilityTagRepair,
    CapabilityTag.software => l10n.capabilityTagSoftware,
    CapabilityTag.design => l10n.capabilityTagDesign,
    CapabilityTag.adminPaperwork => l10n.capabilityTagAdminPaperwork,
    CapabilityTag.time => l10n.capabilityTagTime,
    CapabilityTag.contact => l10n.capabilityTagContact,
    CapabilityTag.other => l10n.capabilityTagOther,
  };
}
