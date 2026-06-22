import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

/// Native-only 3-page onboarding pager (web onboarding lives on the static
/// landing — same copy, see `packages/landing/onboarding.js`).
@RoutePage()
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  static const _pageCount = 3;

  final _controller = PageController();

  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final pages = [
      (title: l10n.introPage1Title, text: l10n.introPage1Text),
      (title: l10n.introPage2Title, text: l10n.introPage2Text),
      (title: l10n.introPage3Title, text: l10n.introPage3Text),
    ];
    final isLast = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        minimum: kPaddingAll,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => Column(
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
                        pages[index].title,
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge,
                      ),
                    ),

                    // Text
                    Padding(
                      padding: kPaddingAllS,
                      child: Text(
                        pages[index].text,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge,
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),

            // Page dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.tt.iconTextGap,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                      ),
                    ),
                  ),
              ],
            ),

            // Next / Start
            Padding(
              padding: kPaddingV,
              child: FilledButton(
                onPressed: isLast
                    ? () => GetIt.I<SettingsCubit>().setIntroEnabled(false)
                    : () => _controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      ),
                child: Text(isLast ? l10n.buttonStart : l10n.buttonNext),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
