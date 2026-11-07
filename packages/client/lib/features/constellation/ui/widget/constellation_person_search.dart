import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/semantics_free_tooltip.dart';

import '../../domain/constellation_people.dart';
import '../../domain/entity/constellation_field_search_result.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_camera_controls.dart';

/// Most people a name search lists at once; typing narrows it further.
const kConstellationPersonSearchLimit = 200;

const _fieldSearchDebounce = Duration(milliseconds: 300);
const _fieldSearchMinLength = 2;

/// Field search (#255): people, Requests and Posts via `fieldSearch`, with
/// local people matching as an offline fallback (#253).
class ConstellationPersonSearchButton extends StatefulWidget {
  const ConstellationPersonSearchButton({super.key});

  @override
  State<ConstellationPersonSearchButton> createState() =>
      _ConstellationPersonSearchButtonState();
}

class _ConstellationPersonSearchButtonState
    extends State<ConstellationPersonSearchButton> {
  Timer? _debounce;
  int _searchSession = 0;
  String? _inFlightQuery;
  String? _resolvedQuery;
  ConstellationFieldSearchResult _resolvedResults =
      emptyConstellationFieldSearchResult;
  Object? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _resetSearchSession() {
    _debounce?.cancel();
    _debounce = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _searchSession++;
      _inFlightQuery = null;
      _resolvedQuery = null;
      _resolvedResults = emptyConstellationFieldSearchResult;
      _searchError = null;
    });
  }

  void _scheduleSearch(ConstellationCubit cubit, String query) {
    _debounce?.cancel();
    if (query.length < _fieldSearchMinLength) {
      setState(() {
        _inFlightQuery = null;
        _resolvedQuery = null;
        _resolvedResults = emptyConstellationFieldSearchResult;
        _searchError = null;
      });
      return;
    }
    final session = _searchSession;
    setState(() => _inFlightQuery = query);
    _debounce = Timer(_fieldSearchDebounce, () async {
      try {
        final results = await cubit.searchField(query);
        if (!mounted || session != _searchSession || _inFlightQuery != query) {
          return;
        }
        setState(() {
          _resolvedQuery = query;
          _inFlightQuery = null;
          _resolvedResults = results;
          _searchError = null;
        });
      } on Object catch (error) {
        if (!mounted || session != _searchSession || _inFlightQuery != query) {
          return;
        }
        setState(() {
          _resolvedQuery = query;
          _inFlightQuery = null;
          _resolvedResults = emptyConstellationFieldSearchResult;
          _searchError = error;
        });
      }
    });
  }

  List<ConstellationFieldPerson> _localPeopleMatches(
    ConstellationCubit cubit,
    String rawQuery, {
    required String viewerId,
  }) {
    return [
      for (final person in cubit.fieldPeople)
        if (person.id != viewerId &&
            constellationPersonMatches(person, rawQuery))
          person,
    ];
  }

  EdgeInsets _cameraInsets(BuildContext context) {
    try {
      return context.read<ConstellationCubit>().fieldCameraViewportInsets(
        context,
        contextPanelVisible: true,
      );
    } on ProviderNotFoundException {
      // List/search-only harnesses mount the cubit above this widget without
      // a Provider scope around the suggestion rows.
      return ConstellationCameraControls.cameraViewportInsets(
        context,
        contextPanelVisible: true,
      );
    }
  }

  void _pickPerson(BuildContext context, ConstellationCubit cubit, String id) {
    cubit.pickFieldSearchPerson(id, insets: _cameraInsets(context));
  }

  void _pickRequest(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationFieldSearchRequestHit hit,
  ) {
    cubit.pickFieldSearchBeacon(
      hit: hit,
      insets: _cameraInsets(context),
      isPost: false,
    );
  }

  void _pickPost(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationFieldSearchPostHit hit,
  ) {
    cubit.pickFieldSearchBeacon(
      hit: ConstellationFieldSearchRequestHit(
        id: hit.id,
        authorId: hit.authorId,
        title: hit.rootExcerpt,
        status: hit.status,
        hidden: hit.hidden,
        lastActivityAt: hit.lastActivityAt,
      ),
      insets: _cameraInsets(context),
      isPost: true,
    );
  }

  String _personLabel(
    ConstellationCubit cubit,
    String personId, {
    String? fallback,
  }) {
    final profile = cubit.profileForPersonId(personId);
    if (profile != null) {
      return profile.shownName;
    }
    final person = cubit.fieldPersonById(personId);
    return person?.displayName ?? fallback ?? personId;
  }

  String _beaconSubtitle(
    L10n l10n,
    ConstellationCubit cubit, {
    required String authorId,
    required DateTime lastActivityAt,
    required int status,
    required bool hidden,
  }) {
    final parts = <String>[_personLabel(cubit, authorId)];
    if (hidden) {
      parts.add(l10n.constellationFieldSearchStatusHidden);
    } else if (!BeaconStatus.fromSmallint(status).isOpenFamily) {
      parts.add(l10n.constellationFieldSearchStatusClosed);
    } else {
      parts.add(
        dateFormatDay(lastActivityAt, locale: l10n.localeName),
      );
    }
    return parts.join(' · ');
  }

  Iterable<Widget> _localPeopleSuggestions(
    BuildContext context,
    ConstellationCubit cubit,
    SearchController controller,
    List<ConstellationFieldPerson> matches, {
    bool grouped = false,
  }) sync* {
    final l10n = L10n.of(context)!;
    if (matches.isEmpty) {
      yield ListTile(
        key: const Key('constellation.search.no_match'),
        title: Text(l10n.constellationFieldSearchEmpty),
      );
      return;
    }
    if (grouped) {
      yield Semantics(
        container: true,
        header: true,
        label: l10n.constellationFieldSearchPeople,
        child: TenturaSectionHeader(label: l10n.constellationFieldSearchPeople),
      );
    }
    for (final person in matches.take(kConstellationPersonSearchLimit)) {
      yield _PersonSuggestion(
        person: person,
        profile: cubit.profileForPersonId(person.id),
        onTap: () {
          controller.closeView(null);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            _pickPerson(context, cubit, person.id);
          });
        },
      );
    }
  }

  Future<Iterable<Widget>> _fieldSearchSuggestions(
    BuildContext context,
    ConstellationCubit cubit,
    SearchController controller,
  ) async {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final raw = controller.text;
    final query = raw.trim();
    final viewerId = cubit.viewerId;

    if (cubit.fieldSearchCase == null) {
      return _localPeopleSuggestions(
        context,
        cubit,
        controller,
        _localPeopleMatches(cubit, raw, viewerId: viewerId),
      ).toList();
    }

    if (query.isEmpty) {
      return [
        ListTile(
          key: const Key('constellation.field_search.prompt'),
          title: Text(l10n.constellationFieldSearchPrompt),
        ),
      ];
    }

    if (query.length < _fieldSearchMinLength) {
      return [
        ListTile(
          key: const Key('constellation.field_search.short_query'),
          title: Text(l10n.constellationFieldSearchMinChars),
        ),
      ];
    }

    if (query != _resolvedQuery && query != _inFlightQuery) {
      _scheduleSearch(cubit, query);
    }
    if (_inFlightQuery == query) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: tt.rowGap),
          child: const Center(child: TenturaCircularProgress()),
        ),
      ];
    }

    final useOfflinePeople =
        _searchError != null || cubit.fieldSearchCase == null;
    final serverPeople = _resolvedResults.people;
    final serverPeopleFiltered = [
      for (final hit in serverPeople)
        if (hit.id != viewerId) hit,
    ];
    final localPeople = useOfflinePeople
        ? _localPeopleMatches(cubit, raw, viewerId: viewerId)
        : const <ConstellationFieldPerson>[];

    if (!useOfflinePeople &&
        serverPeopleFiltered.isEmpty &&
        _resolvedResults.requests.isEmpty &&
        _resolvedResults.posts.isEmpty &&
        localPeople.isEmpty) {
      final onlyViewer =
          serverPeople.isNotEmpty &&
          serverPeople.every((hit) => hit.id == viewerId);
      return [
        ListTile(
          key: const Key('constellation.field_search.empty'),
          title: Text(
            onlyViewer
                ? l10n.constellationFieldSearchSelfOnly
                : l10n.constellationFieldSearchEmpty,
          ),
        ),
      ];
    }

    final widgets = <Widget>[];

    if (useOfflinePeople) {
      if (_searchError != null) {
        widgets.add(
          ListTile(
            key: const Key('constellation.field_search.error'),
            title: Text(l10n.constellationFieldSearchUnavailable),
          ),
        );
      }
      widgets.addAll(
        _localPeopleSuggestions(
          context,
          cubit,
          controller,
          localPeople,
          grouped: true,
        ),
      );
      return widgets;
    }

    if (serverPeopleFiltered.isNotEmpty) {
      widgets.add(
        Semantics(
          container: true,
          header: true,
          label: l10n.constellationFieldSearchPeople,
          child: TenturaSectionHeader(
            label: l10n.constellationFieldSearchPeople,
          ),
        ),
      );
      for (final hit in serverPeopleFiltered) {
        widgets.add(
          ListTile(
            key: Key('constellation.field_search.person.${hit.id}'),
            leading: Icon(Icons.person_outline, size: tt.iconSize),
            title: Text(
              _personLabel(
                cubit,
                hit.id,
                fallback: hit.displayName ?? hit.handle,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              controller.closeView(null);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                _pickPerson(context, cubit, hit.id);
              });
            },
          ),
        );
      }
    }

    if (_resolvedResults.requests.isNotEmpty) {
      widgets.add(
        Semantics(
          container: true,
          header: true,
          label: l10n.constellationFieldSearchRequests,
          child: TenturaSectionHeader(
            label: l10n.constellationFieldSearchRequests,
          ),
        ),
      );
      for (final hit in _resolvedResults.requests) {
        widgets.add(
          ListTile(
            key: Key('constellation.field_search.request.${hit.id}'),
            leading: Icon(Icons.assignment_outlined, size: tt.iconSize),
            title: Text(hit.title, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _beaconSubtitle(
                l10n,
                cubit,
                authorId: hit.authorId,
                lastActivityAt: hit.lastActivityAt,
                status: hit.status,
                hidden: hit.hidden,
              ),
            ),
            onTap: () {
              controller.closeView(null);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                _pickRequest(context, cubit, hit);
              });
            },
          ),
        );
      }
    }

    if (_resolvedResults.posts.isNotEmpty) {
      widgets.add(
        Semantics(
          container: true,
          header: true,
          label: l10n.constellationFieldSearchPosts,
          child: TenturaSectionHeader(
            label: l10n.constellationFieldSearchPosts,
          ),
        ),
      );
      for (final hit in _resolvedResults.posts) {
        widgets.add(
          ListTile(
            key: Key('constellation.field_search.post.${hit.id}'),
            leading: Icon(Icons.article_outlined, size: tt.iconSize),
            title: Text(hit.rootExcerpt, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _beaconSubtitle(
                l10n,
                cubit,
                authorId: hit.authorId,
                lastActivityAt: hit.lastActivityAt,
                status: hit.status,
                hidden: hit.hidden,
              ),
            ),
            onTap: () {
              controller.closeView(null);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                _pickPost(context, cubit, hit);
              });
            },
          ),
        );
      }
    }

    if (widgets.isEmpty) {
      final onlyViewer =
          serverPeople.isNotEmpty &&
          serverPeople.every((hit) => hit.id == viewerId);
      widgets.add(
        ListTile(
          key: const Key('constellation.field_search.empty'),
          title: Text(
            onlyViewer
                ? l10n.constellationFieldSearchSelfOnly
                : l10n.constellationFieldSearchEmpty,
          ),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ConstellationCubit>();
    return SearchAnchor(
      key: TestIds.key(TestIds.constellationFieldSearch),
      viewHintText: l10n.constellationFieldSearchHint,
      viewOnOpen: _resetSearchSession,
      viewOnClose: _resetSearchSession,
      builder: (context, controller) => SemanticsFreeTooltip(
        message: l10n.constellationSearchPeople,
        child: IconButton(
          key: const Key('constellation.app_bar.search'),
          icon: Icon(
            Icons.person_search_outlined,
            semanticLabel: l10n.constellationSearchPeople,
          ),
          constraints: BoxConstraints(
            minWidth: tt.buttonHeight,
            minHeight: tt.buttonHeight,
          ),
          onPressed: controller.openView,
        ),
      ),
      suggestionsBuilder: (viewContext, controller) =>
          _fieldSearchSuggestions(viewContext, cubit, controller),
    );
  }
}

class _PersonSuggestion extends StatelessWidget {
  const _PersonSuggestion({
    required this.person,
    required this.profile,
    required this.onTap,
  });

  final ConstellationFieldPerson person;
  final Profile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    return ListTile(
      key: Key('constellation.search.person.${person.id}'),
      leading: profile == null ? null : TenturaAvatar.small(profile: profile),
      title: Text(
        profile?.shownName ?? person.name,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
