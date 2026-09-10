import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/inbox_cubit.dart';
import '../widget/inbox_triage_list.dart';

@RoutePage()
class InboxTriageScreen extends StatelessWidget implements AutoRouteWrapper {
  const InboxTriageScreen({super.key});

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
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final inboxCubit = context.read<InboxCubit>();
    final attentionCubit = GetIt.I<HomeAttentionCubit>();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: TenturaTopBar.of(
        context,
        tone: TenturaTopBarTone.primary,
        leading: const AutoLeadingButton(),
        title: Text(
          l10n.inboxTabNeedsMe,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.titleLarge(scheme.onPrimary),
        ),
        actions: const [
          InboxTriageSortButton(),
        ],
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
              return BlocBuilder<HomeAttentionCubit, HomeAttentionState>(
                bloc: attentionCubit,
                builder: (context, attention) {
                  return InboxTriageList(
                    inboxCubit: inboxCubit,
                    state: state,
                    attentionMarkerIds: attention.inboxMarkerIds,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
