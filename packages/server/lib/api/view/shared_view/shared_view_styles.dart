import 'package:jaspr/dom.dart';

const kEdgeInsetsS = Unit.pixels(8);
const kEdgeInsetsM = Unit.pixels(16);
const kEdgeInsetsL = Unit.pixels(24);

const kShadowColorVarName = '--shadow-color';

// Uncomment next line for hot reload styles
// List<StyleRule> get defaultStyles => [
final defaultStyles = [
  // Vars
  css(':root').styles(
    raw: {
      kShadowColorVarName: const Color('#D4DEF7').value,
    },
  ),
  css.media(
    const MediaQuery.all(prefersColorScheme: ColorScheme.dark),
    [
      css(':root').styles(
        raw: {
          kShadowColorVarName: const Color('#1F1D37').value,
        },
      ),
    ],
  ),

  // Tags
  css('body').styles(
    width: 100.percent,
    minHeight: 100.vh,
    margin: Spacing.zero,
    color: Colors.black.withLightness(0.2),
    fontFamily: FontFamilies.sansSerif,
    backgroundColor: Colors.azure,
  ),

  css('article').styles(
    display: Display.flex,
    minHeight: const Unit.vh(100),
    flexDirection: FlexDirection.column,
    flex: const Flex(grow: 1),
    backgroundColor: Colors.aliceBlue,
  ),

  css('section').styles(
    padding: const Spacing.all(kEdgeInsetsM),
  ),

  css('small').styles(
    color: Colors.slateGray,
    fontSize: 12.px,
  ),

  // Dark Theme
  css.media(
    const MediaQuery.all(prefersColorScheme: ColorScheme.dark),
    [
      css('body').styles(
        color: Colors.ghostWhite,
        backgroundColor: Colors.darkSlateBlue,
      ),

      css('article').styles(
        backgroundColor: const Color('#30344D'),
      ),
    ],
  ),

  // large screens
  css.media(
    MediaQuery.screen(minWidth: 480.px),
    [
      css('body').styles(
        display: Display.flex,
        justifyContent: JustifyContent.center,
        alignItems: AlignItems.center,
      ),

      css('article').styles(
        minHeight: Unit.auto,
        maxWidth: const Unit.pixels(360),
        radius: const BorderRadius.circular(Unit.pixels(8)),
        shadow: const BoxShadow(
          offsetX: Unit.zero,
          offsetY: Unit.pixels(8),
          blur: Unit.pixels(16),
          spread: Unit.pixels(6),
          color: Color.variable(kShadowColorVarName),
        ),
      ),
    ],
  ),
];
