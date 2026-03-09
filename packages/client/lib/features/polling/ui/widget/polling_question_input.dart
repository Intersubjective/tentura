import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class PollingQuestionInput extends StatelessWidget {
  const PollingQuestionInput({
    required this.onChanged,
    this.initialValue,
    this.labelText,
    super.key,
  });

  final String? labelText;

  final String? initialValue;

  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    decoration: InputDecoration(
      labelText: labelText,
    ),
    maxLines: 5,
    minLines: 1,
    initialValue: initialValue,
    keyboardType: TextInputType.text,
    maxLength: Polling.questionMaxLength,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    onTapOutside: (_) => FocusScope.of(context).unfocus(),
    onChanged: onChanged,
    validator: (value) {
      if (value != null && value.isNotEmpty) {
        try {
          Polling.questionValidator(value);
        } on PollingInputExceptions catch (e) {
          return e.toL10n(L10n.of(context)!.localeName);
        }
      }
      return null;
    },
  );
}
