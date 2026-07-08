import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/notification_center_item.dart';
import '../bloc/notification_center_cubit.dart';

@RoutePage()
class NotificationCenterScreen extends StatelessWidget
    implements AutoRouteWrapper {
  const NotificationCenterScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = NotificationCenterCubit();
      unawaited(cubit.fetch());
      return cubit;
    },
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.notifications),
        actions: [
          BlocSelector<NotificationCenterCubit, NotificationCenterState, bool>(
            selector: (s) => s.items.any((e) => !e.isRead),
            builder: (context, hasUnread) => TextButton(
              onPressed: hasUnread
                  ? () => context.read<NotificationCenterCubit>().markAllRead()
                  : null,
              child: Text(l10n.notificationsMarkAllRead),
            ),
          ),
        ],
      ),
      body: TenturaContentColumn(
        child: BlocBuilder<NotificationCenterCubit, NotificationCenterState>(
          builder: (context, state) {
            if (state.isLoading && state.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.isEmpty) {
              return _EmptyState(l10n: l10n);
            }
            return RefreshIndicator(
              onRefresh: context.read<NotificationCenterCubit>().fetch,
              child: ListView.separated(
                itemCount: state.items.length,
                separatorBuilder: (_, _) => const TenturaHairlineDivider(),
                itemBuilder: (context, index) => _NotificationTile(
                  item: state.items[index],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationCenterItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = context.tt;
    final titleColor = item.isRead ? tt.textMuted : colors.onSurface;
    return ListTile(
      leading: Icon(
        _iconFor(item.category),
        size: tt.iconSize,
        color: item.isRead ? tt.textMuted : _accentFor(context, item.category),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TenturaText.title(titleColor).copyWith(
          fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        item.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TenturaText.bodySmall(tt.textMuted),
      ),
      trailing: Text(
        _shortAge(item.createdAt),
        style: TenturaText.bodySmall(tt.textFaint),
      ),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    await context.read<NotificationCenterCubit>().markRead(item.id);
    await GetIt.I<RootRouter>().openFromNotificationLink(item.actionUrl);
  }

  static IconData _iconFor(NotificationCenterCategory category) =>
      switch (category) {
        NotificationCenterCategory.asksOfMe =>
          Icons.notifications_active_outlined,
        NotificationCenterCategory.unblocksMe => Icons.check_circle_outline,
        NotificationCenterCategory.coordination => Icons.forum_outlined,
        NotificationCenterCategory.connections => Icons.people_alt_outlined,
        NotificationCenterCategory.ambient => Icons.bubble_chart_outlined,
        NotificationCenterCategory.unknown => Icons.notifications_outlined,
      };

  static Color _accentFor(
    BuildContext context,
    NotificationCenterCategory category,
  ) {
    final tt = context.tt;
    return switch (category) {
      NotificationCenterCategory.asksOfMe => tt.danger,
      NotificationCenterCategory.unblocksMe => tt.good,
      NotificationCenterCategory.coordination => tt.info,
      NotificationCenterCategory.connections => tt.good,
      NotificationCenterCategory.ambient ||
      NotificationCenterCategory.unknown => tt.textMuted,
    };
  }

  static String _shortAge(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tt = context.tt;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: tt.iconSize * 2,
            color: tt.textFaint,
          ),
          SizedBox(height: tt.rowGap),
          Text(
            l10n.notificationsEmpty,
            style: TenturaText.title(colors.onSurface),
          ),
          SizedBox(height: tt.tightGap),
          Text(
            l10n.notificationsEmptyHint,
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ],
      ),
    );
  }
}
