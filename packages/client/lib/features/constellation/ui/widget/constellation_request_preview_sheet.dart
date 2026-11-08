import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import '../../domain/entity/constellation_field_target_kind.dart';
import 'constellation_field_item_actions.dart';
import 'constellation_field_preview_people_rows.dart';
import 'constellation_pin_placeholder_sheet.dart';
import 'constellation_request_label.dart';
import 'constellation_request_status_marker.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../bloc/constellation_cubit.dart';

/// Below this peek height the preview scrolls body and actions together so the
/// layout never overflows; at phone peek sizes Pin / Hide stay pinned (#255).
const _kFieldPreviewPinnedFooterMinHeight = 168.0;

/// Primary action label for the preview action matrix (held state × coverage).
String constellationPreviewPrimaryActionLabel(
  L10n l10n,
  ConstellationRequest request,
) {
  return switch (request.heldState) {
    ConstellationHeldState.mine => l10n.openBeacon,
    ConstellationHeldState.offered => l10n.beaconCtaEditHelpOffer,
    ConstellationHeldState.participant => l10n.openBeacon,
    ConstellationHeldState.forwarded => l10n.openBeacon,
    ConstellationHeldState.none => switch (BeaconStatus.fromSmallint(
      request.status,
    )) {
      BeaconStatus.enoughHelp => l10n.beaconOfferHelpAsBackup,
      _ => l10n.labelOfferHelp,
    },
  };
}

/// People tab when the viewer already holds an offer (edit on the card).
String? constellationHeldOpenViewTab(ConstellationHeldState held) =>
    held == ConstellationHeldState.offered ? kBeaconViewTabPeople : null;

/// Whether Forward is shown as a permitted secondary action.
bool constellationPreviewShowsForward(ConstellationRequest request) {
  if (request.isMine || request.isPlaceholder) {
    return false;
  }
  return BeaconStatus.fromSmallint(request.status).isOpenFamily;
}

/// In-stack request preview card for Constellation (adaptive overlay child).
class ConstellationRequestPreviewSheet extends StatelessWidget {
  const ConstellationRequestPreviewSheet({
    required this.request,
    required this.authorDisplayName,
    this.connectionThroughName,
    this.onOpen,
    this.onPrimaryAction,
    this.onForward,
    this.onShowForwardTreeOnField,
    this.onOpenParticipants,
    this.onOpenForwardedThrough,
    this.onClose,
    this.now,
    super.key,
  });

  final ConstellationRequest request;
  final String authorDisplayName;
  final String? connectionThroughName;
  final VoidCallback? onOpen;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onForward;
  final VoidCallback? onShowForwardTreeOnField;
  final VoidCallback? onOpenParticipants;
  final VoidCallback? onOpenForwardedThrough;
  final VoidCallback? onClose;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (request.isPlaceholder) {
      return ConstellationPinPlaceholderSheet(
        target: ConstellationAnchorTarget.beacon(request.id),
        pinState: request.pinState,
        onClose: onClose,
      );
    }
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final scheme = theme.colorScheme;
    final clock = now ?? DateTime.now();
    final status = BeaconStatus.fromSmallint(request.status);
    final heldAnnotation = constellationHeldAnnotation(l10n, request);
    final connectionLabel = constellationConnectionLabelText(
      l10n,
      throughPeerName: connectionThroughName,
    );
    final primaryLabel = constellationPreviewPrimaryActionLabel(l10n, request);
    final showForward =
        constellationPreviewShowsForward(request) && onForward != null;
    final showForwardTree = onShowForwardTreeOnField != null;
    final showOpenButton =
        onOpen != null &&
        (onPrimaryAction == null || primaryLabel != l10n.openBeacon);

    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOpenButton)
          OutlinedButton(
            onPressed: onOpen,
            child: Text(l10n.openBeacon),
          ),
        if (onPrimaryAction != null) ...[
          if (showOpenButton) SizedBox(height: tt.rowGap),
          FilledButton(
            key: const Key('constellation.request_preview.primary'),
            onPressed: onPrimaryAction,
            child: Text(primaryLabel),
          ),
        ],
        if (showForward) ...[
          SizedBox(height: tt.rowGap),
          OutlinedButton.icon(
            onPressed: onForward,
            icon: const Icon(Icons.send_outlined),
            label: Text(l10n.labelForward),
          ),
        ],
        if (showForwardTree) ...[
          SizedBox(height: tt.rowGap),
          OutlinedButton(
            key: const Key('constellation.request_preview.forward_tree'),
            onPressed: onShowForwardTreeOnField,
            child: Text(l10n.constellationPreviewShowForwardTreeOnField),
          ),
        ],
        SizedBox(height: tt.rowGap),
        BlocBuilder<ConstellationCubit, ConstellationState>(
          buildWhen: (previous, current) =>
              previous.selectedRequestId != current.selectedRequestId ||
              previous.graphRevision != current.graphRevision,
          builder: (context, _) {
            final cubit = context.read<ConstellationCubit>();
            if (!cubit.isSearchRevealedHiddenBeacon(request.id)) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(bottom: tt.rowGap),
              child: OutlinedButton(
                key: TestIds.key(TestIds.constellationShowAgain),
                onPressed: () => unawaited(
                  cubit.unhideSearchHiddenBeacon(request.id),
                ),
                child: Text(l10n.constellationShowAgain),
              ),
            );
          },
        ),
        ConstellationFieldItemFooterActions(
          targetKind: ConstellationFieldTargetKind.request,
          beaconId: request.id,
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _titleLine(l10n),
                style: theme.textTheme.titleMedium,
              ),
            ),
            SizedBox(width: tt.tightGap),
            BlocBuilder<ConstellationCubit, ConstellationState>(
              buildWhen: (previous, current) =>
                  previous.graphRevision != current.graphRevision ||
                  previous.field != current.field,
              builder: (context, _) {
                final cubit = context.read<ConstellationCubit>();
                return ConstellationRequestStatusMarker(
                  rawStatus: request.status,
                  isPinned: cubit.isAnchored(
                    ConstellationAnchorTarget.beacon(request.id),
                  ),
                );
              },
            ),
            if (onClose != null)
              IconButton(
                tooltip: l10n.buttonClose,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        if (heldAnnotation != null) ...[
          SizedBox(height: tt.tightGap),
          TenturaStatusText(
            heldAnnotation,
            tone: TenturaTone.info,
          ),
        ],
        SizedBox(height: tt.sectionGap),
        _PreviewSection(
          title: l10n.constellationPreviewWhenTitle,
          body: _whenLine(l10n, clock),
        ),
        if (_locationLine(l10n) != null) ...[
          SizedBox(height: tt.rowGap),
          _PreviewSection(
            title: l10n.constellationPreviewWhereTitle,
            body: _locationLine(l10n)!,
          ),
        ],
        SizedBox(height: tt.rowGap),
        _PreviewSection(
          title: l10n.constellationPreviewCoverageTitle,
          body: [
            ?_needsLine(l10n),
            coordinationStatusLabel(l10n, status),
          ].join('\n'),
        ),
        if (connectionLabel != null) ...[
          SizedBox(height: tt.sectionGap),
          Text(
            connectionLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tt.tightGap),
          Text(
            l10n.constellationNotReferral,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: tt.sectionGap),
        ConstellationFieldPreviewPeopleRows(
          beaconId: request.id,
          isPost: false,
          onOpenParticipants: onOpenParticipants,
          onOpenForwardedThrough: onOpenForwardedThrough,
        ),
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.constellationPreviewAuthorLine(authorDisplayName),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Material(
      key: const Key('constellation.request_preview'),
      color: scheme.surfaceContainerHigh,
      elevation: 4,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: tt.cardPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pinFooter =
                constraints.maxHeight.isFinite &&
                constraints.maxHeight >= _kFieldPreviewPinnedFooterMinHeight;
            if (!constraints.maxHeight.isFinite) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(child: body),
                  SizedBox(height: tt.rowGap),
                  footer,
                ],
              );
            }
            if (!pinFooter) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    body,
                    SizedBox(height: tt.rowGap),
                    footer,
                  ],
                ),
              );
            }
            // Peek-height compact sheets: keep Pin / Hide on screen (#255, #974).
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: SingleChildScrollView(child: body)),
                SizedBox(height: tt.rowGap),
                Flexible(
                  child: SingleChildScrollView(
                    child: footer,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The title leads, as on the request itself (#355); the need text only
  /// stands in when there is no title.
  String _titleLine(L10n l10n) {
    final title = request.title.trim();
    return title.isNotEmpty ? title : constellationNeedText(l10n, request);
  }

  /// The requested capabilities, in the author's order (#355).
  String? _needsLine(L10n l10n) {
    final labels = [
      for (final slug in request.needs)
        ?CapabilityTag.fromSlug(slug)?.labelOf(l10n),
    ];
    return labels.isEmpty ? null : labels.join(', ');
  }

  String _whenLine(L10n l10n, DateTime clock) {
    return constellationTimingSnippet(l10n, request, now: clock) ??
        l10n.constellationUnspecified;
  }

  String? _locationLine(L10n l10n) {
    final label = request.addressLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    if (request.hasCoordinates) {
      return l10n.constellationLocationPinned;
    }
    return null;
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TenturaTypeLabel(title),
        SizedBox(height: tt.tightGap),
        Text(
          body,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
