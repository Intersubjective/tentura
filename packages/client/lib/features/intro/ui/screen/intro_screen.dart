import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

@RoutePage()
class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        minimum: kPaddingAll,
        child: Column(
          children: [
            const Spacer(),

            // Image
            const SvgPicture(
              AssetBytesLoader('images/intro.svg.vec'),
            ),

            // Title
            Padding(
              padding: kPaddingAllS,
              child: Text(
                l10n.introTitle,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge,
              ),
            ),

            // Text
            Padding(
              padding: kPaddingAllS,
              child: Text(
                l10n.introText,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge,
              ),
            ),

            const Spacer(),

            // Continue Button
            Padding(
              padding: kPaddingV,
              child: FilledButton(
                onPressed: () =>
                    GetIt.I<SettingsCubit>().setIntroEnabled(false),
                child: Text(l10n.buttonStart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
