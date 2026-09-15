import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'constellation_anchor_controls.dart';
import 'constellation_request_label.dart';
import 'constellation_request_status_marker.dart';

import '../../domain/entity/constellation_anchor.dart';
import '../bloc/constellation_cubit.dart';

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
    ConstellationHeldState.none => switch (
      BeaconStatus.fromSmallint(request.status)
    ) {
      BeaconStatus.enoughHelp => l10n.beaconOfferHelpAsBackup,
      _ => l10n.labelOfferHelp,
    },
  };
}

/// People tab when the viewer already holds an offer (edit on the card).
String? constellationHeldOpenViewTab(ConstellationHeldState held) =>
    held == ConstellationHeldState.offered ? kBeaconViewTabPeople : null;

/// Whether [Forward] is shown as a permitted secondary action.
bool constellationPreviewShowsForward(ConstellationRequest request) {
  if (request.isMine) {
    return false;
  }
  return BeaconStatus.fromSmallint(request.status).isOpenFamily;
}

Future<void> showConstellationRequestPreviewSheet({
  required BuildContext context,
  required ConstellationRequest request,
  required String authorDisplayName,
  String? connectionThroughName,
  VoidCallback? onOpen,
  VoidCallback? onPrimaryAction,
  VoidCallback? onForward,
  DateTime? now,
}) {
  final cubit = context.read<ConstellationCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => BlocProvider.value(
      value: cubit,
      child: ConstellationRequestPreviewSheet(
        request: request,
        authorDisplayName: authorDisplayName,
        connectionThroughName: connectionThroughName,
        onOpen: onOpen,
        onPrimaryAction: onPrimaryAction,
        onForward: onForward,
        now: now,
      ),
    ),
  );
}

class ConstellationRequestPreviewSheet extends StatelessWidget {
  const ConstellationRequestPreviewSheet({
    required this.request,
    required this.authorDisplayName,
    this.connectionThroughName,
    this.onOpen,
    this.onPrimaryAction,
    this.onForward,
    this.now,
    super.key,
  });

  final ConstellationRequest request;
  final String authorDisplayName;
  final String? connectionThroughName;
  final VoidCallback? onOpen;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onForward;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
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
    final showOpenButton = onOpen != null &&
        (onPrimaryAction == null || primaryLabel != l10n.openBeacon);

    return SafeArea(
      child: Padding(
        key: const Key('constellation.request_preview'),
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.rowGap,
          tt.screenHPadding,
          tt.sectionGap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    constellationNeedText(l10n, request),
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
              ],
            ),
            if (heldAnnotation != null) ...[
              SizedBox(height: tt.tightGap),
              TenturaStatusText(
                heldAnnotation,
                tone: TenturaTone.info,
                maxLines: 2,
                softWrap: true,
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
              body: coordinationStatusLabel(l10n, status),
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
            Text(
              l10n.constellationPreviewAuthorLine(authorDisplayName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tt.sectionGap),
            // Drop outlined Open when primary already is Open (mine /
            // participant / forwarded) — same destination, duplicate CTA.
            if (showOpenButton)
              OutlinedButton(
                onPressed: onOpen,
                child: Text(l10n.openBeacon),
              ),
            if (onPrimaryAction != null) ...[
              if (showOpenButton) SizedBox(height: tt.rowGap),
              FilledButton(
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
            SizedBox(height: tt.rowGap),
            ConstellationAnchorTargetButton(
              target: ConstellationAnchorTarget.beacon(request.id),
              filled: true,
            ),
          ],
        ),
      ),
    );
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
