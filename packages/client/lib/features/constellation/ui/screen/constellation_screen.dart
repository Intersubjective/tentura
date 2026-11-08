import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.gr.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/ui/widget/lazy_write_timeout_notice.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_tab_transition_listener.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/widget/graph_trust_write_notices.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/scheduling/adaptive_slice_controller.dart';
import 'package:tentura/ui/util/frame_slice_scheduler.dart';
import 'package:tentura/ui/util/rearrange_preview_scheduler.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../domain/use_case/constellation_member_webs_case.dart';
import '../../domain/use_case/constellation_mutual_trust_case.dart';
import '../../domain/use_case/constellation_new_people_case.dart';
import '../../domain/use_case/constellation_trust_chain_case.dart';
import '../../domain/use_case/constellation_tag_magnet_case.dart';
import '../../domain/use_case/constellation_anchor_case.dart';
import '../../domain/use_case/constellation_placement_case.dart';
import '../../domain/use_case/constellation_field_store_case.dart';
import '../../domain/use_case/constellation_field_hide_case.dart';
import '../../domain/use_case/constellation_field_search_case.dart';
import '../../domain/use_case/constellation_person_field_items_case.dart';
import '../../domain/use_case/constellation_visibility_case.dart';
import '../util/layout_geometry_adapters.dart';
import '../../domain/constellation_presence.dart';
import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';
import '../bloc/constellation_cubit.dart';
import '../bloc/constellation_presence_cubit.dart';
import '../bloc/constellation_selection_cubit.dart';
import '../bloc/constellation_tag_lens_cubit.dart';
import '../scene/constellation_scene_controller.dart';
import '../util/constellation_focus_request.dart';
import '../util/constellation_forward_tree_request.dart';
import '../widget/constellation_app_bar.dart';
import '../widget/constellation_body.dart';
import '../widget/constellation_create_entry.dart';
import '../widget/field_collapsing_app_bar.dart';

@RoutePage()
class ConstellationScreen extends StatefulWidget implements AutoRouteWrapper {
  const ConstellationScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    // `ConstellationCubit`/`GraphPersonContextCubit` capture `viewer` once,
    // at construction time, not reactively — so if this screen is the very
    // first thing built after a cold load (e.g. a deep link straight into
    // this tab, before `ProfileCubit`'s own async fetch resolves), a
    // synchronous `GetIt.I<ProfileCubit>().state.profile` read would freeze
    // in an empty placeholder (empty id, empty display name) for the whole
    // Cubit's lifetime. Gate construction on the profile actually being
    // loaded instead.
    child: BlocBuilder<ProfileCubit, ProfileState>(
      bloc: GetIt.I<ProfileCubit>(),
      buildWhen: (previous, current) =>
          previous.profile.id != current.profile.id,
      builder: (context, profileState) {
        final viewer = profileState.profile;
        if (viewer.id.isEmpty) {
          return const Center(child: TenturaCircularProgress());
        }
        return BlocProvider(
          create: (_) {
            final layoutSlicer = FrameSliceScheduler(
              clock: GetIt.I<ClockPort>(),
              wakeUpPort: GetIt.I<WakeUpPort>(),
              controller: AdaptiveSliceController(
                initialUnitCost: const Duration(microseconds: 100),
              ),
            );
            final rearrangeSlicer = FrameSliceRearrangePreviewScheduler(
              FrameSliceScheduler(
                clock: GetIt.I<ClockPort>(),
                wakeUpPort: GetIt.I<WakeUpPort>(),
                controller: AdaptiveSliceController(
                  initialUnitCost: const Duration(microseconds: 100),
                ),
              ),
            );
            return ConstellationCubit(
              case_: GetIt.I<ConstellationFieldStoreCase>(),
              anchorCase: GetIt.I<ConstellationAnchorCase>(),
              placementCase: GetIt.I<ConstellationPlacementCase>(),
              memberWebsCase: GetIt.I<ConstellationMemberWebsCase>(),
              visibilityCase: GetIt.I<ConstellationVisibilityCase>(),
              fieldHideCase: GetIt.I<ConstellationFieldHideCase>(),
              fieldSearchCase: GetIt.I<ConstellationFieldSearchCase>(),
              personFieldItemsCase:
                  GetIt.I<ConstellationPersonFieldItemsCase>(),
              mutualTrustCase: GetIt.I<ConstellationMutualTrustCase>(),
              trustChainCase: GetIt.I<ConstellationTrustChainCase>(),
              newPeopleCase: GetIt.I<ConstellationNewPeopleCase>(),
              tagMagnetCase: GetIt.I<ConstellationTagMagnetCase>(),
              ownTagIdsOf: GetIt.I.isRegistered<PeopleTagsCase>()
                  ? GetIt.I<PeopleTagsCase>().tagsOfPerson
                  : null,
              peopleInTag: GetIt.I.isRegistered<PeopleTagsCase>()
                  ? GetIt.I<PeopleTagsCase>().peopleInTag
                  : null,
              viewer: viewer,
              scene: ConstellationSceneController(
                slicer: layoutSlicer,
                rearrangePreviewScheduler: rearrangeSlicer,
              ),
            );
          },
          child: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => ConstellationSelectionCubit()),
              BlocProvider(
                create: (_) => GetIt.I.isRegistered<PeopleTagsCase>()
                    ? ConstellationTagLensCubit(
                        ownTagIdsOf: GetIt.I<PeopleTagsCase>().tagsOfPerson,
                      )
                    : ConstellationTagLensCubit(),
              ),
              // Friends' presence on the field: watched for the people on
              // it, re-diffed only when the field or its composition change.
              BlocProvider(
                lazy: false,
                create: (context) {
                  final constellation = context.read<ConstellationCubit>();
                  Set<String> watchIdsOf(ConstellationState state) =>
                      constellationPresenceWatchIds(
                        field: state.field,
                        composition: state.composition,
                        viewerId: viewer.id,
                      );
                  return ConstellationPresenceCubit(
                    initialWatchIds: watchIdsOf(constellation.state),
                    watchIds: constellation.stream
                        .distinct(
                          (a, b) =>
                              identical(a.field, b.field) &&
                              identical(a.composition, b.composition),
                        )
                        .map(watchIdsOf),
                  );
                },
              ),
              BlocProvider(
                create: (context) => GraphPersonContextCubit(
                  profileViewCase: GetIt.I<ProfileViewCase>(),
                  trustWriteCase: GetIt.I<GraphTrustWriteCase>(),
                  viewerId: viewer.id,
                ),
              ),
              BlocProvider(
                create: (context) {
                  final constellation = context.read<ConstellationCubit>();
                  return ConstellationComposerCubit(
                    positions: const {},
                    eligible: const {},
                    peopleSnapshot: constellation.composerPeople,
                    personName: constellation.composerPersonName,
                    createCubitFactory: (kind) => BeaconCreateCubit(kind: kind),
                    forwardCubitFactory: (beaconId) =>
                        ForwardCubit(beaconId: beaconId, embedded: true),
                  );
                },
              ),
            ],
            child: this,
          ),
        );
      },
    ),
  );

  @override
  State<ConstellationScreen> createState() => _ConstellationScreenState();
}

class _ConstellationScreenState extends State<ConstellationScreen> {
  bool _legendExpanded = false;
  bool _fieldContextSheetExpanded = false;

  void _toggleLegend() => setState(() => _legendExpanded = !_legendExpanded);

  void _onFieldContextSheetExpanded(bool expanded) {
    if (_fieldContextSheetExpanded == expanded) {
      return;
    }
    setState(() => _fieldContextSheetExpanded = expanded);
  }

  final _focusRequest = ConstellationFocusRequest.instance;
  final _forwardTreeRequest = ConstellationForwardTreeRequest.instance;

  StackRouter? _rootRouter;
  TabsRouter? _homeTabs;

  /// The root's URL history. A root route popped by its navigator (the back
  /// button, a swipe, `maybePop`) leaves through `StackRouter.onPopPage`,
  /// which rebuilds the URL but does not notify the root router itself.
  Listenable? _history;

  /// Whether the field is already in the composing phase for the composer.
  bool _composing = false;

  late final GraphController<NodeDetails, EdgeDetails> _graphController;

  // The one zoom-level owner the map body and its overlay both read.
  final _zoomLevel = ConstellationZoomLevelController();

  @override
  void initState() {
    super.initState();
    // People positions reach the composer from the interaction layer, so a
    // drag or a layout move never recomposes the field.
    _graphController = context.read<ConstellationCubit>().graphController
      ..addListener(_syncComposerPersonPositions);
    _focusRequest.pending.addListener(_takeFocusRequest);
    _forwardTreeRequest.pending.addListener(_takeForwardTreeRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _takeFocusRequest();
      _takeForwardTreeRequest();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No router (isolated widget tests): treated as always visible.
    final root = StackRouterScope.of(context)?.controller.root;
    final tabs = root?.innerRouterOf<TabsRouter>(HomeRoute.name);
    final history = root?.navigationHistory;
    if (!identical(root, _rootRouter) ||
        !identical(tabs, _homeTabs) ||
        !identical(history, _history)) {
      _rootRouter?.removeListener(_syncVisibility);
      _homeTabs?.removeListener(_syncVisibility);
      _history?.removeListener(_syncVisibility);
      _rootRouter = root?..addListener(_syncVisibility);
      _homeTabs = tabs?..addListener(_syncVisibility);
      _history = history?..addListener(_syncVisibility);
    }
    _syncVisibility();
  }

  @override
  void dispose() {
    _graphController.removeListener(_syncComposerPersonPositions);
    _rootRouter?.removeListener(_syncVisibility);
    _homeTabs?.removeListener(_syncVisibility);
    _history?.removeListener(_syncVisibility);
    _focusRequest.pending.removeListener(_takeFocusRequest);
    _forwardTreeRequest.pending.removeListener(_takeForwardTreeRequest);
    _zoomLevel.dispose();
    super.dispose();
  }

  /// The field is visible while the Constellation tab is active and no root
  /// route (a Request, a profile, …) covers Home. Hidden, it stops fetching
  /// and watching presence.
  void _syncVisibility() {
    if (!mounted) return;
    final tabs = _homeTabs;
    final root = _rootRouter;
    final tabActive =
        tabs == null ||
        tabs.activeIndex == HomeTabSpec.forTab(HomeTab.constellation).index;
    final homeOnTop = root == null || root.current.name == HomeRoute.name;
    final visible = tabActive && homeOnTop;
    if (!visible) {
      maybeConstellationSelection(context)?.exitArranging();
    }
    context.read<ConstellationCubit>().setVisible(visible);
    // Hidden, the field asks for nobody's presence either.
    context.read<ConstellationPresenceCubit?>()?.setVisible(visible);
  }

  void _syncComposerPersonPositions() {
    if (!mounted) return;
    final composer = maybeConstellationComposer(context);
    if (composer == null || composer.isClosed || composer.createCubit == null) {
      return;
    }
    composer.updatePersonPositions(_personPositions());
  }

  Map<String, Offset> _personPositions() {
    final snapshot = _graphController.renderSnapshot;
    return {
      for (final entry in snapshot.topology.nodesById.entries)
        if (entry.value.payload case FieldPersonNode(:final id))
          if (snapshot.resolvePosition(entry.key) case final position?)
            id: Offset(position.x, position.y),
    };
  }

  /// Focuses a beacon another screen asked for, once the field is loaded.
  void _takeFocusRequest() {
    if (!mounted || _focusRequest.pending.value == null) return;
    final cubit = context.read<ConstellationCubit>();
    if (cubit.state.status is! StateIsSuccess || cubit.state.isComposing) {
      return;
    }
    final beaconId = _focusRequest.take();
    if (beaconId == null) return;
    // A frame later, so a field that has just loaded is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tt = context.tt;
      final compact = context.windowClass == WindowClass.compact;
      final effectiveAppBarHeight = compact && _fieldContextSheetExpanded
          ? 0.0
          : tt.appBarHeight;
      final mapBodyHeight =
          MediaQuery.sizeOf(context).height -
          effectiveAppBarHeight -
          tt.bottomNavHeight;
      cubit.focusBeacon(
        beaconId,
        insets: cubit.fieldCameraViewportInsets(
          context,
          contextPanelVisible: true,
          compactSheetHeight: context.windowClass == WindowClass.compact
              ? mapBodyHeight * tt.fieldSheetPeekFraction
              : 0,
        ),
      );
    });
  }

  void _takeForwardTreeRequest() {
    if (!mounted || _forwardTreeRequest.pending.value == null) return;
    final cubit = context.read<ConstellationCubit>();
    if (cubit.state.status is! StateIsSuccess || cubit.state.isComposing) {
      return;
    }
    final payload = _forwardTreeRequest.take();
    if (payload == null) return;
    if (GetIt.I.isRegistered<HomeTabReselectCubit>()) {
      GetIt.I<HomeTabReselectCubit>().bump(HomeTab.constellation);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.read<ConstellationCubit>().enterForwardTreeMode(
          beaconId: payload.beaconId,
          helpOffererFocusId: payload.helpOffererId,
        ),
      );
    });
  }

  @override
  void deactivate() {
    maybeConstellationSelection(context)?.exitArranging();
    final cubit = context.read<ConstellationCubit>();
    if (!cubit.state.isComposing) {
      cubit.onRouteLeave();
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final composer = maybeConstellationComposer(context);
    return MultiBlocListener(
      listeners: [
        if (composer != null)
          BlocListener<ConstellationComposerCubit, RadiusRecipientSelection>(
            bloc: composer,
            // The scene is recomposed only when the session starts or ends or
            // who can be addressed changes; a moving circle or person is not.
            listenWhen: (prev, curr) =>
                _composing != (composer.createCubit != null) ||
                !setEquals(prev.eligible, curr.eligible),
            listener: (context, selection) {
              final constellation = context.read<ConstellationCubit>();
              _composing = composer.createCubit != null;
              if (!_composing) {
                constellation.exitComposing(
                  pinPersonIds: composer.sentInCircleIds,
                );
                unawaited(constellation.load());
              } else {
                context.read<ConstellationSelectionCubit>().exitArranging();
                constellation.enterComposing(
                  draftCentre: selection.center.offset,
                  candidateIds: selection.eligible,
                  selectedIds: selection.selected,
                  onToggle: composer.toggleMapRecipient,
                );
              }
            },
          ),
        if (composer != null)
          BlocListener<ConstellationComposerCubit, RadiusRecipientSelection>(
            bloc: composer,
            listenWhen: (prev, curr) =>
                prev.center != curr.center ||
                !setEquals(prev.selected, curr.selected),
            listener: (context, selection) =>
                context.read<ConstellationCubit>().followComposer(
                  draftCentre: selection.center.offset,
                  selectedIds: selection.selected,
                ),
          ),
        if (composer != null)
          BlocListener<ConstellationCubit, ConstellationState>(
            listenWhen: (prev, curr) =>
                !identical(prev.field, curr.field) && curr.isComposing,
            listener: (context, _) => composer.refreshPeople(),
          ),
        // A composing scene rebuild has placed the people it shows; the
        // first ones placed size the composer's circle.
        if (composer != null)
          BlocListener<ConstellationCubit, ConstellationState>(
            listenWhen: (prev, curr) =>
                prev.graphRevision != curr.graphRevision && curr.isComposing,
            listener: (context, _) {
              if (composer.createCubit != null) {
                composer.peoplePlaced(_personPositions());
              }
            },
          ),
        BlocListener<ConstellationCubit, ConstellationState>(
          listenWhen: (prev, curr) =>
              prev.status is! StateIsSuccess && curr.status is StateIsSuccess,
          listener: (context, _) {
            _takeFocusRequest();
            _takeForwardTreeRequest();
          },
        ),
        BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
          listenWhen: (prev, curr) =>
              prev.constellationReselectCount !=
              curr.constellationReselectCount,
          listener: (context, _) {
            unawaited(context.read<ConstellationCubit>().load());
          },
        ),
      ],
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final selectionCubit = maybeConstellationSelection(context);
    final compact = context.windowClass == WindowClass.compact;
    final topBar = TenturaTopBar.of(
      context,
      title: const SizedBox.shrink(),
      row: ConstellationAppBarRow(
        legendExpanded: _legendExpanded,
        onToggleLegend: _toggleLegend,
      ),
      account: homeTopBarAccount(context),
    );
    final scaffold = Scaffold(
      appBar: FieldCollapsingAppBar(
        key: const Key('field.context_sheet.app_bar'),
        collapsed: compact && _fieldContextSheetExpanded,
        bar: topBar,
      ),
      body: GraphTrustWriteNotices(
        child: LazyWriteTimeoutNotice(
          notices: context.read<ConstellationCubit>().lazyWriteNotices,
          child: RepositoryProvider<ConstellationZoomLevelController>.value(
            value: _zoomLevel,
            child: TenturaFullBleed(
              child: ConstellationBody(
                legendExpanded: _legendExpanded,
                onToggleLegend: _toggleLegend,
                onFieldContextSheetExpandedChanged: compact
                    ? _onFieldContextSheetExpanded
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    Widget wrapped = scaffold;
    final tabs = _homeTabs;
    if (tabs != null && selectionCubit != null) {
      wrapped = HomeTabTransitionListener(
        tabsRouter: tabs,
        tab: HomeTab.constellation,
        onLeave: selectionCubit.exitArranging,
        child: wrapped,
      );
    }
    if (selectionCubit == null) {
      return wrapped;
    }
    return BlocBuilder<
      ConstellationSelectionCubit,
      ConstellationMultiSelection
    >(
      bloc: selectionCubit,
      builder: (context, selectionState) => PopScope(
        canPop: !selectionState.arranging,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (selectionState.arranging) {
            selectionCubit.exitArranging();
          }
        },
        child: wrapped,
      ),
    );
  }
}
