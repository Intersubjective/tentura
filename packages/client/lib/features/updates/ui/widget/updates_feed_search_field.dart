import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class UpdatesFeedSearchField extends StatelessWidget {
  const UpdatesFeedSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final radius = BorderRadius.all(Radius.circular(tt.searchBarRadius));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
      child: SizedBox(
        height: tt.searchBarHeight,
        // The hint is gone once text is typed; keep the field named (#425).
        child: Semantics(
          label: hintText,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TenturaText.body(tt.text),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TenturaText.body(tt.textMuted),
              filled: true,
              fillColor: tt.surface,
              prefixIcon: Icon(Icons.search, color: tt.textMuted),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: L10n.of(context)!.updatesSearchClear,
                      icon: const Icon(Icons.clear_outlined),
                      onPressed: onClear,
                    ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
              ),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: tt.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: tt.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: tt.info),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
