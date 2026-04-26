import 'package:flutter/material.dart';

class ColorsDrawer extends StatelessWidget {
  const ColorsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Drawer(
      child: DefaultTextStyle(
        style: theme.textTheme.titleSmall!.copyWith(height: 2),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Primary',
                style: TextStyle(
                  backgroundColor: colorScheme.primary,
                  color: colorScheme.onPrimary,
                )),
            Text('PrimaryContainer',
                style: TextStyle(
                  backgroundColor: colorScheme.primaryContainer,
                  color: colorScheme.onPrimaryContainer,
                )),
            Text('Secondary',
                style: TextStyle(
                  backgroundColor: colorScheme.secondary,
                  color: colorScheme.onSecondary,
                )),
            Text('SecondaryContainer',
                style: TextStyle(
                  backgroundColor: colorScheme.secondaryContainer,
                  color: colorScheme.onSecondaryContainer,
                )),
            Text('Tertiary',
                style: TextStyle(
                  backgroundColor: colorScheme.tertiary,
                  color: colorScheme.onTertiary,
                )),
            Text('TertiaryContainer',
                style: TextStyle(
                  backgroundColor: colorScheme.tertiaryContainer,
                  color: colorScheme.onTertiaryContainer,
                )),
            Text('Background',
                style: TextStyle(
                  backgroundColor: colorScheme.surface,
                  color: colorScheme.onSurface,
                )),
            Text('Surface',
                style: TextStyle(
                  backgroundColor: colorScheme.surface,
                  color: colorScheme.onSurface,
                )),
            Text('SurfaceVariant',
                style: TextStyle(
                  backgroundColor: colorScheme.surfaceContainer,
                  color: colorScheme.onSurfaceVariant,
                )),
            Text('Error',
                style: TextStyle(
                  backgroundColor: colorScheme.error,
                  color: colorScheme.onError,
                )),
            Text('scaffoldBackgroundColor',
                style: TextStyle(
                  backgroundColor: theme.scaffoldBackgroundColor,
                  color: theme.primaryColor,
                )),
          ],
        ),
      ),
    );
  }
}
