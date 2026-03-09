import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/polling/ui/widget/polling_question_input.dart';
import 'package:tentura/features/polling/ui/widget/polling_variant_input.dart';

import '../bloc/beacon_create_cubit.dart';

class PollingTab extends StatelessWidget {
  const PollingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<BeaconCreateCubit>();
    return ListView(
      children: [
        // Poll Question
        PollingQuestionInput(
          key: ValueKey(cubit),
          labelText: l10n.pollQuestionFieldLabel,
          initialValue: cubit.state.question,
          onChanged: cubit.setQuestion,
        ),

        // Label for Variants
        Padding(
          padding: kPaddingT,
          child: Text(
            l10n.pollOptionsLabel,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),

        // Variants
        BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
          bloc: cubit,
          builder: (context, state) => Column(
            children: [
              for (var i = 0; i < state.variants.length; i++)
                PollingVariantInput(
                  key: state.variantsKeys[i],
                  labelText: l10n.optionLabel(i + 1),
                  initialValue: state.variants[i],
                  onRemove: () => cubit.removeVariant(i),
                  onChanged: (value) => cubit.setVariant(i, value),
                ),
            ],
          ),
        ),

        // Add Variant
        Padding(
          padding: kPaddingLargeV,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: Text(l10n.addOptionButton),
            onPressed: cubit.addVariant,
          ),
        ),
      ],
    );
  }
}
