import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'beacon_tile.dart';

/// The body shared by the beacon list screens: first-load spinner, error
/// with Retry, pull-to-refresh empty state, and the paged list that asks
/// for the next page near the end of the scroll.
class BeaconPagedList extends StatefulWidget {
  const BeaconPagedList({
    required this.beacons,
    required this.isLoading,
    required this.hasError,
    required this.onFetchMore,
    required this.onReload,
    required this.empty,
    this.showAuthor = true,
    super.key,
  });

  final List<Beacon> beacons;

  final bool isLoading;

  final bool hasError;

  /// Next page (the cubit's `fetch()`).
  final Future<void> Function() onFetchMore;

  /// From the first page (the cubit's `fetch(reset: true)`): Retry and
  /// pull-to-refresh.
  final Future<void> Function() onReload;

  /// The empty-state content, centred in the pull-to-refresh area.
  final Widget empty;

  /// Passed to each [BeaconTile].
  final bool showAuthor;

  @override
  State<BeaconPagedList> createState() => _BeaconPagedListState();
}

class _BeaconPagedListState extends State<BeaconPagedList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients &&
          _scrollController.offset >
              _scrollController.position.maxScrollExtent * kFetchListOffset) {
        unawaited(widget.onFetchMore());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final beacons = widget.beacons;

    if (widget.isLoading && beacons.isEmpty) {
      return const Center(
        child: TenturaCircularProgress(adaptive: true),
      );
    }
    if (widget.hasError && beacons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: scheme.error,
            ),
            const SizedBox(height: kSpacingMedium),
            FilledButton(
              onPressed: () => unawaited(widget.onReload()),
              child: Text(L10n.of(context)!.myWorkRetry),
            ),
          ],
        ),
      );
    }
    if (beacons.isEmpty) {
      return RefreshIndicator.adaptive(
        onRefresh: widget.onReload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.4,
              child: Center(
                child: Padding(
                  padding: tt.cardPadding,
                  child: widget.empty,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: widget.onReload,
      child: ListView.builder(
        key: ValueKey(beacons),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kPaddingSmallV,
        itemCount: beacons.length,
        itemBuilder: (_, i) {
          final beacon = beacons[i];
          return Padding(
            padding: kPaddingSmallV,
            child: BeaconTile(
              key: ValueKey(beacon.id),
              beacon: beacon,
              showAuthor: widget.showAuthor,
              onOpenBeacon: () => context.router.push(
                BeaconViewRoute(id: beacon.id),
              ),
              onForward: () => context.router.push(
                ForwardBeaconRoute(beaconId: beacon.id),
              ),
            ),
          );
        },
      ),
    );
  }
}
