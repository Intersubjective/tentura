import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Search box above a long `CapabilityChipSet`; pass its text as the set's
/// `query` (#741).
class CapabilitySearchField extends StatefulWidget {
  const CapabilitySearchField({required this.onChanged, super.key});

  static const fieldKey = Key('Capability.SearchField');

  /// The field's own semantics node (#741).
  static const semanticsKey = Key('Capability.SearchField.Semantics');

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
    final empty = _controller.text.isEmpty;
    // Its own semantics node under the sheet's Focus ancestor, so the web
    // engine keeps the typing focus on this field (#741).
    return Semantics(
      key: CapabilitySearchField.semanticsKey,
      container: true,
      child: TextField(
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
              // Stays mounted, disabled, when the field is empty: a pointer
              // left on it after a clear keeps its tooltip and the typing
              // focus (#741). «Очистить поиск», not Material's «Удалить
              // текст»: it empties the search.
              suffixIcon: IconButton(
                tooltip: l10n.capabilitySearchClear,
                onPressed: empty
                    ? null
                    : () {
                        _controller.clear();
                        _changed('');
                      },
                icon: const Icon(Icons.clear),
              ),
            ),
      ),
    );
  }
}
