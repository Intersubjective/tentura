import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/inbox_item.dart';
import '../bloc/inbox_cubit.dart';
import '../widget/inbox_watchlist_row.dart';
import '../widget/inbox_card_actions.dart';
import '../widget/rejection_dialog.dart';

@RoutePage()
class InboxWatchingScreen extends StatefulWidget implements AutoRouteWrapper {
  const InboxWatchingScreen({
    @QueryParam(kQueryInboxWatchingHighlight) this.highlightBeaconId,
    super.key,
  });

  final String? highlightBeaconId;

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, accountId) => BlocProvider(
          key: ValueKey(accountId),
          create: (_) {
            final cubit = InboxCubit(userId: accountId);
            unawaited(cubit.fetch());
            return cubit;
          },
          child: this,
        ),
      );

  @override
  State<InboxWatchingScreen> createState() => _InboxWatchingScreenState();
}

class _InboxWatchingScreenState extends State<InboxWatchingScreen> {
  final _scrollController = ScrollController();
  final _itemKeys = <String, GlobalKey>{};

  String? _highlightBeaconId;
  var _highlightConsumed = false;

  @override
  void initState() {
    super.initState();
    final id = widget.highlightBeaconId?.trim();
    if (id != null && id.isNotEmpty) {
      _highlightBeaconId = id;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlightIfNeeded(List<InboxItem> items) {
    if (_highlightConsumed || _highlightBeaconId == null) return;
    final target = _highlightBeaconId!;
    if (!items.any((e) => e.beaconId == target)) return;
    _highlightConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _itemKeys[target]?.currentContext;
      if (context == null) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.15,
          duration: const Duration(milliseconds: 320),
        ),
      );
    });
  }

  GlobalKey _keyFor(String beaconId) =>
      _itemKeys.putIfAbsent(beaconId, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final inboxCubit = context.read<InboxCubit>();
    final highlightId = _highlightConsumed ? null : _highlightBeaconId;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.inboxWatching),
      ),
      body: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: TenturaContentColumn(
          child: BlocBuilder<InboxCubit, InboxState>(
            buildWhen: (_, c) => c.isSuccess || c.isLoading,
            builder: (_, state) {
              if (state.isLoading && !state.projectionLoaded) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }
              final items = state.watching;
              _scrollToHighlightIfNeeded(items);
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: tt.cardPadding,
                    child: Text(
                      l10n.inboxWatchingEmptyCalm,
                      style: TenturaText.bodyMedium(
                        scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: inboxCubit.fetch,
                child: ListView.separated(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return InboxWatchlistRow(
                      key: _keyFor(item.beaconId),
                      item: item,
                      isSelected: highlightId == item.beaconId,
                      onOpenBeacon: () => context.router.push(
                        BeaconViewRoute(
                          id: item.beaconId,
                          entry: kBeaconEntryInbox,
                        ),
                      ),
                      onTap: item.beacon?.allowsForward == true
                          ? () => unawaited(inboxForwardItem(context, item))
                          : null,
                      onStopWatching: () =>
                          unawaited(inboxCubit.stopWatching(item.beaconId)),
                      onDismissFromInbox: () async {
                        final msg = await showInboxDismissDialog(context);
                        if (!context.mounted) return;
                        if (msg != null) {
                          await inboxCubit.reject(item.beaconId, message: msg);
                        }
                      },
                      onCantHelp: () async {
                        final msg = await showRejectionDialog(context);
                        if (!context.mounted) return;
                        if (msg != null) {
                          await inboxCubit.reject(item.beaconId, message: msg);
                        }
                      },
                      onOfferHelp: inboxCardAllowsOfferHelp(item)
                          ? () => inboxOfferHelp(context, item.beacon!)
                          : null,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
