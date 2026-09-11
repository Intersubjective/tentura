import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/constellation_anchor.dart';
import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_anchor_controls.dart';
import 'constellation_overflow_group.dart';
import 'constellation_request_label.dart';
import 'constellation_request_status_marker.dart';

/// Accessible list alternative to the constellation map (UX6 / §11.3).
///
/// Uses the same snapshot, filters, and request ids as the map — not a second
/// query. When [ConstellationCubit.peersCapped] is true, connection paths are
/// suppressed (plain list recovery mode).
class ConstellationTextView extends StatefulWidget {
  const ConstellationTextView({super.key});

  @override
  State<ConstellationTextView> createState() => _ConstellationTextViewState();
}

class _ConstellationTextViewState extends State<ConstellationTextView> {
  final Set<String> _announcedOverflowAuthors = {};

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConstellationCubit, ConstellationState>(
      listenWhen: (previous, current) =>
          previous.graphRevision != current.graphRevision ||
          previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
          previous.filterLocation != current.filterLocation ||
          previous.filterTiming != current.filterTiming ||
          previous.filterIncludeUnspecified !=
              current.filterIncludeUnspecified,
      listener: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        for (final authorId in cubit.overflowHiddenCountByAuthor.keys) {
          if (cubit.isSatelliteOverflowExpanded(authorId) &&
              _announcedOverflowAuthors.add(authorId)) {
            SemanticsService.announce(
              L10n.of(context)!.constellationMoreRequests(
                cubit.overflowHiddenCountByAuthor[authorId] ?? 0,
              ),
              TextDirection.ltr,
            );
          }
        }
      },
      buildWhen: (previous, current) =>
          previous.field != current.field ||
          previous.paths != current.paths ||
          previous.graphRevision != current.graphRevision ||
          previous.selectedRequestId != current.selectedRequestId ||
          previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
          previous.filterLocation != current.filterLocation ||
          previous.filterTiming != current.filterTiming ||
          previous.filterIncludeUnspecified !=
              current.filterIncludeUnspecified ||
          previous.loadError != current.loadError,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final theme = Theme.of(context);

        if (state.loadError != null && state.field == null) {
          return Semantics(
            liveRegion: true,
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                child: Text(
                  state.loadError.toString(),
                  key: const Key('constellation.text.error'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          );
        }

        final field = state.field;
        if (field == null) {
          return const SizedBox.shrink();
        }

        final authorIds = _authorIdsWithEligibleRequests(cubit, field);
        if (authorIds.isEmpty) {
          return Semantics(
            liveRegion: true,
            label: l10n.constellationEmptyFiltered,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(tt.screenHPadding),
                child: Text(
                  cubit.hasActiveFilters
                      ? l10n.constellationEmptyFiltered
                      : l10n.constellationTextEmptyField,
                  key: const Key('constellation.text.empty'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          );
        }

        final suppressConnections = cubit.peersCapped;
        final loadedAt = state.loadedAt ?? field.loadedAt;

        return Semantics(
          label: l10n.constellationTextViewSemantics,
          child: ListView(
            key: const Key('constellation.text.list'),
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.rowGap,
            ),
            children: [
              if (suppressConnections)
                Padding(
                  padding: EdgeInsets.only(bottom: tt.rowGap),
                  child: Text(
                    l10n.constellationPlainListNotice,
                    key: const Key('constellation.text.plain_list_notice'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final authorId in authorIds) ...[
                _PersonRequestGroup(
                  authorId: authorId,
                  suppressConnections: suppressConnections,
                  loadedAt: loadedAt,
                  selectedRequestId: state.selectedRequestId,
                  onSelectRequest: cubit.selectRequest,
                ),
                SizedBox(height: tt.sectionGap),
              ],
            ],
          ),
        );
      },
    );
  }

  List<String> _authorIdsWithEligibleRequests(
    ConstellationCubit cubit,
    ConstellationField field,
  ) {
    final ids = <String>{};
    for (final request in field.requests) {
      if (cubit.discoverableRequestsForPerson(request.authorId).any(
        (eligible) => eligible.id == request.id,
      )) {
        ids.add(request.authorId);
      }
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }
}

class _PersonRequestGroup extends StatelessWidget {
  const _PersonRequestGroup({
    required this.authorId,
    required this.suppressConnections,
    required this.loadedAt,
    required this.selectedRequestId,
    required this.onSelectRequest,
  });

  final String authorId;
  final bool suppressConnections;
  final DateTime loadedAt;
  final String? selectedRequestId;
  final ValueChanged<String?> onSelectRequest;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ConstellationCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final profile = cubit.profileForPersonId(authorId);
    final displayName = profile?.shownName ?? authorId;

    final eligible = cubit.discoverableRequestsForPerson(authorId);
    final visibleIds = cubit.isSatelliteOverflowExpanded(authorId)
        ? eligible.map((request) => request.id).toList()
        : [
            for (final request in eligible)
              if (cubit.displayedRequestIds.contains(request.id)) request.id,
          ];
    final hiddenCount = cubit.overflowHiddenCountByAuthor[authorId] ?? 0;
    final paths = cubit.state.paths;

    return Semantics(
      container: true,
      header: true,
      label: displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        key: Key('constellation.text.person.$authorId'),
        children: [
          Text(
            displayName,
            style: theme.textTheme.titleSmall,
          ),
          SizedBox(height: tt.tightGap),
          for (final request in eligible)
            if (visibleIds.contains(request.id))
              _RequestTile(
                request: request,
                selected: selectedRequestId == request.id,
                connectionLabel: suppressConnections || paths == null
                    ? null
                    : constellationConnectionLabelText(
                        l10n,
                        throughPeerName: _throughPeerName(cubit, request),
                      ),
                loadedAt: loadedAt,
                onSelect: () => onSelectRequest(request.id),
              ),
          if (hiddenCount > 0)
            Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstellationOverflowGroup(
                  authorId: authorId,
                  hiddenCount: hiddenCount,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _throughPeerName(
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) {
    final paths = cubit.state.paths;
    if (paths == null) {
      return null;
    }
    final throughPeerId = constellationConnectionThroughPeerId(
      egoId: cubit.viewerId,
      authorId: request.authorId,
      parent: paths.parent,
    );
    if (throughPeerId == null) {
      return null;
    }
    return cubit.profileForPersonId(throughPeerId)?.shownName;
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.selected,
    required this.connectionLabel,
    required this.loadedAt,
    required this.onSelect,
  });

  final ConstellationRequest request;
  final bool selected;
  final String? connectionLabel;
  final DateTime loadedAt;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final held = constellationHeldAnnotation(l10n, request);
    final label = constellationRequestLabelText(
      l10n,
      request,
      now: loadedAt,
    );
    final cubit = context.read<ConstellationCubit>();
    final isPinned = cubit.isAnchored(
      ConstellationAnchorTarget.beacon(request.id),
    );
    final markerSemantics = constellationRequestMarkerSemantics(
      l10n: l10n,
      tt: tt,
      rawStatus: request.status,
      isPinned: isPinned,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: [
        label,
        if (connectionLabel != null) connectionLabel,
        if (held != null) held,
        ...markerSemantics,
      ].join('. '),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          key: Key('constellation.text.request.${request.id}'),
          onTap: onSelect,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: tt.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    ConstellationRequestStatusMarker(
                      rawStatus: request.status,
                      isPinned: isPinned,
                    ),
                  ],
                ),
                SizedBox(height: tt.tightGap),
                ConstellationAnchorTargetButton(
                  target: ConstellationAnchorTarget.beacon(request.id),
                ),
                if (connectionLabel != null) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    connectionLabel!,
                    key: Key('constellation.text.connection.${request.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (held != null) ...[
                  SizedBox(height: tt.tightGap),
                  TenturaStatusText(
                    held,
                    tone: TenturaTone.info,
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
