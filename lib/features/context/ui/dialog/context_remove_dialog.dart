import 'package:flutter/material.dart';

class ContextRemoveDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (context) => const ContextRemoveDialog(),
      );

  const ContextRemoveDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Are you shure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
        ],
      );
}
