import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class PollingVariantInput extends StatelessWidget {
  const PollingVariantInput({
    required this.onChanged,
    required this.onRemove,
    this.initialValue,
    this.labelText,
    super.key,
  });

  final String? initialValue;

  final String? labelText;

  final void Function() onRemove;

  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    decoration: InputDecoration(
      labelText: labelText,
      suffix: IconButton(
        color: Theme.of(context).colorScheme.error,
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: onRemove,
      ),
    ),
    maxLines: 3,
    minLines: 1,
    initialValue: initialValue,
    keyboardType: TextInputType.text,
    maxLength: Polling.variantMaxLength,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    onTapOutside: (_) => FocusScope.of(context).unfocus(),
    onChanged: onChanged,
    validator: (value) {
      if (value != null && value.isNotEmpty) {
        try {
          Polling.variantValidator(value);
        } on PollingInputExceptions catch (e) {
          return e.toL10n(L10n.of(context)!.localeName);
        }
      }
      return null;
    },
  );
}
