import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/context_cubit.dart';
import '../dialog/context_add_dialog.dart';
import '../dialog/context_remove_dialog.dart';

class ContextDropDown extends StatelessWidget {
  const ContextDropDown({
    required this.onChanged,
    super.key,
  });

  final Future<void> Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ContextCubit>();
    return BlocConsumer<ContextCubit, ContextState>(
      builder: (context, state) => DropdownButton<String>(
        key: ValueKey(state),
        isExpanded: true,
        items: [
          DropdownMenuItem(
            child: TextButton(
              child: const Text('Add new context'),
              onPressed: () async {
                final newContext = await ContextAddDialog.show(context);
                if (newContext != null) {
                  if (context.mounted) await context.maybePop();
                  await cubit.add(newContext);
                  await onChanged(newContext);
                }
              },
            ),
          ),
          const DropdownMenuItem(
            value: '',
            child: Text('All contexts'),
          ),
          for (final e in state.contexts)
            DropdownMenuItem(
              value: e,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e),
                  IconButton(
                    icon: const Icon(Icons.delete_forever),
                    onPressed: () async {
                      if (await ContextRemoveDialog.show(context) ?? false) {
                        if (context.mounted) await context.maybePop();
                        await cubit.delete(e);
                        await onChanged('');
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
        onChanged: (value) async {
          cubit.select(value);
          await onChanged(value);
        },
        value: state.selected,
      ),
      listenWhen: (p, c) => c.hasError,
      listener: showSnackBarError,
    );
  }
}
