import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Search box above a long `CapabilityChipSet`; pass its text as the set's
/// `query` (#741).
class CapabilitySearchField extends StatefulWidget {
  const CapabilitySearchField({required this.onChanged, super.key});

  static const fieldKey = Key('Capability.SearchField');

  final ValueChanged<String> onChanged;

  @override
  State<CapabilitySearchField> createState() => _CapabilitySearchFieldState();
}

class _CapabilitySearchFieldState extends State<CapabilitySearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return TextField(
      key: CapabilitySearchField.fieldKey,
      controller: _controller,
      style: tenturaFormFieldTextStyle(context),
      textInputAction: TextInputAction.search,
      onChanged: _changed,
      decoration:
          tenturaFormFieldDecoration(
            context,
            labelText: l10n.capabilitySearchLabel,
          ).copyWith(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    onPressed: () {
                      _controller.clear();
                      _changed('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
    );
  }
}
