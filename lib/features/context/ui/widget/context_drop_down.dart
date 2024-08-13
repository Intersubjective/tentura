import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/context_cubit.dart';
import '../dialog/context_add_dialog.dart';
import '../dialog/context_remove_dialog.dart';

class ContextDropDown extends StatelessWidget {
  const ContextDropDown({
    this.onChanged,
    super.key,
  });

  final void Function(String?)? onChanged;

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
                  await cubit.add(newContext);
                  if (context.mounted) Navigator.of(context).pop();
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
                        await cubit.delete(e);
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          cubit.select(value);
          onChanged?.call(value);
        },
        value: state.selected,
      ),
      listenWhen: (p, c) => c.hasError,
      listener: showSnackBarError,
    );
  }
}
