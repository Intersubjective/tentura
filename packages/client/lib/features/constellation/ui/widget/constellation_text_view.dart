import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/constellation_people.dart';
import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_anchor_controls.dart';
import 'constellation_no_contacts.dart';
import 'constellation_overflow_group.dart';
import 'constellation_request_label.dart';
import 'constellation_request_status_marker.dart';

/// The field as a list (UX6 / §11.3, #253): the map's people, direct
/// contacts first, each with their Requests and Posts as secondary rows, and
/// a name search that filters the list.
///
/// Uses the same snapshot, population, filters, and request ids as the map —
/// not a second query. When [ConstellationCubit.peersCapped] is true,
/// connection paths are suppressed (plain list recovery mode).
class ConstellationTextView extends StatefulWidget {
  const ConstellationTextView({super.key});

  @override
  State<ConstellationTextView> createState() => _ConstellationTextViewState();
}

class _ConstellationTextViewState extends State<ConstellationTextView> {
  final Set<String> _announcedOverflowAuthors = {};
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConstellationCubit, ConstellationState>(
      listenWhen: (previous, current) =>
          previous.graphRevision != current.graphRevision ||
          previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
          previous.filterLocation != current.filterLocation ||
          previous.filterTiming != current.filterTiming ||
          previous.filterIncludeUnspecified != current.filterIncludeUnspecified,
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
      buildWhen: (previous, current) {
        // Hidden behind the map: skip; switching to the view rebuilds it.
        if (current.viewMode != ConstellationViewMode.text) return false;
        if (previous.viewMode != ConstellationViewMode.text) return true;
        return previous.field != current.field ||
            previous.paths != current.paths ||
            previous.composition != current.composition ||
            previous.graphRevision != current.graphRevision ||
            previous.selectedRequestId != current.selectedRequestId ||
            previous.selectedPersonId != current.selectedPersonId ||
            previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
            previous.filterLocation != current.filterLocation ||
            previous.filterTiming != current.filterTiming ||
            previous.filterIncludeUnspecified !=
                current.filterIncludeUnspecified ||
            previous.visibility != current.visibility ||
            previous.loadError != current.loadError;
      },
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>()..noteTextViewBuild();
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

        // The map's people (#253): the viewer only when they have something
        // on the field, everyone else always.
        final people = [
          for (final person in cubit.fieldPeople)
            if (!person.isViewer || _hasRows(cubit, person.id)) person,
        ];
        if (people.isEmpty &&
            !cubit.hasActiveFilters &&
            !cubit.hasHiddenLayers &&
            constellationFieldHasNoContacts(field, cubit.viewerId)) {
          // #252: nobody on the field yet — say what to do, not just
          // "no requests".
          return const ConstellationNoContactsEmptyState();
        }
        if (people.isEmpty) {
          return Semantics(
            liveRegion: true,
            label: l10n.constellationEmptyFiltered,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(tt.screenHPadding),
                child: Text(
                  cubit.hasActiveFilters || cubit.hasHiddenLayers
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
        final matching = [
          for (final person in people)
            if (constellationPersonMatches(person, _query)) person,
        ];
        final direct = [
          for (final person in matching)
            if (!person.isViewer && person.isDirectContact) person,
        ];
        final others = [
          for (final person in matching)
            if (!person.isViewer && !person.isDirectContact) person,
        ];

        Widget personGroup(ConstellationFieldPerson person) => Padding(
          padding: EdgeInsets.only(bottom: tt.sectionGap),
          child: _PersonRequestGroup(
            person: person,
            suppressConnections: suppressConnections,
            loadedAt: loadedAt,
            selectedRequestId: state.selectedRequestId,
            selectedPersonId: state.selectedPersonId,
            onSelectRequest: cubit.selectRequest,
          ),
        );

        final items = <Widget>[
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
          if (matching.isEmpty)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.constellationSearchNoMatch,
                key: const Key('constellation.text.search.no_match'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final person in matching)
            if (person.isViewer) personGroup(person),
          // Sections only when the field has both kinds of people.
          if (direct.isNotEmpty && others.isNotEmpty)
            TenturaSectionHeader(
              key: const Key('constellation.text.section.direct'),
              label: l10n.constellationListDirectContacts,
              count: direct.length,
            ),
          for (final person in direct) personGroup(person),
          if (direct.isNotEmpty && others.isNotEmpty)
            TenturaSectionHeader(
              key: const Key('constellation.text.section.others'),
              label: l10n.constellationListOthers,
              count: others.length,
            ),
          for (final person in others) personGroup(person),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: tt.screenHPadding,
                top: tt.rowGap,
                right: tt.screenHPadding,
              ),
              child: SearchBar(
                key: const Key('constellation.text.search'),
                controller: _search,
                hintText: l10n.constellationSearchHint,
                leading: const Icon(Icons.search),
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      key: const Key('constellation.text.search.clear'),
                      tooltip: l10n.constellationSearchClear,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
                ],
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: Semantics(
                label: l10n.constellationListSemantics,
                child: ListView.builder(
                  key: const PageStorageKey<String>('constellation.text.list'),
                  padding: EdgeInsets.symmetric(
                    horizontal: tt.screenHPadding,
                    vertical: tt.rowGap,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => items[index],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _hasRows(ConstellationCubit cubit, String personId) =>
      cubit.discoverableRequestsForPerson(personId).isNotEmpty ||
      cubit.postsForPerson(personId).isNotEmpty;
}

class _PersonRequestGroup extends StatelessWidget {
  const _PersonRequestGroup({
    required this.person,
    required this.suppressConnections,
    required this.loadedAt,
    required this.selectedRequestId,
    required this.selectedPersonId,
    required this.onSelectRequest,
  });

  final ConstellationFieldPerson person;
  final bool suppressConnections;
  final DateTime loadedAt;
  final String? selectedRequestId;
  final String? selectedPersonId;
  final ValueChanged<String?> onSelectRequest;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ConstellationCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final authorId = person.id;
    final profile = cubit.profileForPersonId(authorId);
    final displayName = person.name;

    final eligible = cubit.discoverableRequestsForPerson(authorId);
    final visibleIds = cubit.isSatelliteOverflowExpanded(authorId)
        ? eligible.map((request) => request.id).toList()
        : [
            for (final request in eligible)
              if (cubit.displayedRequestIds.contains(request.id)) request.id,
          ];
    final hiddenCount = cubit.overflowHiddenCountByAuthor[authorId] ?? 0;
    final posts = cubit.postsForPerson(authorId);
    final paths = cubit.state.paths;

    return Semantics(
      container: true,
      header: true,
      label: displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        key: Key('constellation.text.person.$authorId'),
        children: [
          _PersonRow(
            person: person,
            profile: profile,
            selected: selectedPersonId == authorId,
            onTap: person.isViewer ? null : () => cubit.selectPerson(authorId),
          ),
          if (person.contactOnly)
            Padding(
              padding: EdgeInsets.only(bottom: tt.tightGap),
              child: TenturaMetaText(
                l10n.constellationContactOnlyNote,
                key: Key('constellation.text.contact_only.$authorId'),
                maxLines: 3,
              ),
            ),
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
          for (final post in posts)
            _PostTile(
              post: post,
              selected: selectedRequestId == post.id,
              onSelect: () => onSelectRequest(post.id),
            ),
          if (hiddenCount > 0)
            Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstellationOverflowGroup(
                  authorId: authorId,
                  authorName: displayName,
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

/// A person's own row: avatar and name; tapping opens their person panel.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final ConstellationFieldPerson person;
  final Profile? profile;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    final profile = this.profile;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('constellation.text.person_row.${person.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: EdgeInsets.only(bottom: tt.tightGap),
            child: Row(
              children: [
                if (profile != null) ...[
                  TenturaAvatar.tiny(profile: profile, isSelf: person.isViewer),
                  SizedBox(width: tt.avatarTextGap),
                ],
                Expanded(
                  child: Text(
                    person.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Post on the field, a secondary row under its author (#253).
class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    required this.selected,
    required this.onSelect,
  });

  final ConstellationPost post;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${l10n.constellationListPostLabel}. ${post.rootExcerpt}',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          key: Key('constellation.text.post.${post.id}'),
          onTap: onSelect,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: tt.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: tt.iconSize,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: tt.iconTextGap),
                Expanded(
                  child: Text(
                    post.rootExcerpt,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final card = constellationRequestCardText(
      l10n,
      request,
      now: loadedAt,
    );
    final meta = card.meta;
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
      identifier: TestIds.constellationTextRequest(request.id),
      label: [
        card.title,
        ?meta,
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
                // The card is read once, by its label (#678); the visible
                // title, meta and status are excluded, the Pin button below
                // stays its own node.
                ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.title,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (meta != null)
                              Text(
                                meta,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      ConstellationRequestStatusMarker(
                        rawStatus: request.status,
                        isPinned: isPinned,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: tt.tightGap),
                ConstellationAnchorTargetButton(
                  target: ConstellationAnchorTarget.beacon(request.id),
                ),
                if (connectionLabel != null) ...[
                  SizedBox(height: tt.tightGap),
                  ExcludeSemantics(
                    child: Text(
                      connectionLabel!,
                      key: Key('constellation.text.connection.${request.id}'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (held != null) ...[
                  SizedBox(height: tt.tightGap),
                  ExcludeSemantics(
                    child: TenturaStatusText(
                      held,
                      tone: TenturaTone.info,
                      maxLines: 2,
                    ),
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
