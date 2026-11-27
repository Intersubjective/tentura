import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/email_discoverability_cubit.dart';

class EmailDiscoverabilityControl extends StatelessWidget {
  const EmailDiscoverabilityControl({required this.l10n, super.key})
    : _explainer = false;

  const EmailDiscoverabilityControl.explainer({
    required this.l10n,
    super.key,
  }) : _explainer = true;

  final L10n l10n;
  final bool _explainer;

  @override
  Widget build(BuildContext context) {
    final cubit = GetIt.I.maybeGet<EmailDiscoverabilityCubit>();
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<EmailDiscoverabilityCubit, EmailDiscoverabilityState?>(
      bloc: cubit,
      builder: (context, state) {
        if (state == null || (_explainer && state.explainerDismissed)) {
          return const SizedBox.shrink();
        }
        return _explainer ? _card(context, state, cubit) : _tile(state, cubit);
      },
    );
  }

  Widget _tile(
    EmailDiscoverabilityState state,
    EmailDiscoverabilityCubit cubit,
  ) => TenturaMenuTile(
    icon: Icons.alternate_email,
    title: l10n.settingsEmailDiscoverability,
    onTap: state.saving ? null : () => cubit.setEnabled(!state.enabled),
    opensPage: false,
    trailing: Switch(
      value: state.enabled,
      onChanged: state.saving ? null : cubit.setEnabled,
    ),
  );

  Widget _card(
    BuildContext context,
    EmailDiscoverabilityState state,
    EmailDiscoverabilityCubit cubit,
  ) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.rowGap,
      ),
      child: TenturaTechCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tt.tightGap,
          children: [
            Text(
              l10n.emailDiscoverabilityExplainerTitle,
              style: TenturaText.titleSmall(tt.text),
            ),
            Text(
              l10n.emailDiscoverabilityExplainerBody,
              style: TenturaText.bodyMedium(tt.textMuted),
            ),
            _tile(state, cubit),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TenturaTextAction(
                label: l10n.buttonDismiss,
                minInteractive: true,
                onPressed: state.saving ? null : cubit.dismissExplainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
