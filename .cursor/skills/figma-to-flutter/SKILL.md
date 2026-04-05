---
name: figma-to-flutter
description: >-
  Implements a Figma selection or node URL as production-quality Flutter UI for
  this monorepo (packages/client), using MCP design context and screenshot
  verification. Use when the user mentions Figma, a frame, node, component,
  screen, MCP, or "implement this design"; when a Figma selection is active; or
  when a Figma frame/layer link is provided for Flutter UI work.
---

# Figma to Flutter

Implement a Figma selection or Figma node link as production-quality Flutter for this repository.

## Figma MCP prerequisites

For Figma operations that require the plugin MCP (writes or deep reads in file context), load and follow the **`figma-use`** skill before any `use_figma` tool calls, per project tooling rules.

## Repository conventions

Align with this repo’s architecture and codegen rules: `.cursor/rules/*.mdc`, `DEV_GUIDELINES.md` at the repo root. After adding screens (`@RoutePage()`), Freezed types, or other codegen, run `dart run build_runner build -d`.

## Use this skill when

- The user mentions Figma, a frame, a node, a component, a screen, MCP, or "implement this design"
- A Figma selection is active in the desktop app
- A Figma frame/layer URL is provided
- The task is to recreate or update UI in Flutter from Figma

## Goal

Translate the selected Figma design into idiomatic, maintainable Flutter code with high visual fidelity. Do not output web, React, Tailwind, HTML, or CSS except when briefly referencing the MCP payload internally.

## Required workflow

1. Fetch Figma design context for the exact selected node(s).
2. If the response is too large, fetch metadata, identify the exact child nodes needed, and re-fetch only those nodes.
3. Fetch a screenshot for visual verification.
4. Inspect variables, styles, spacing, typography, corner radius, effects, icons, and image assets present in the Figma payload.
5. Only after steps 1–4, implement the Flutter UI.
6. Before finishing, compare the generated UI against the screenshot and fix any visible mismatch.

## Translation rules

- Treat the Figma MCP output as a representation of structure and behavior, not as final code style.
- Convert the design into Flutter widgets and this repo's conventions.
- Prefer existing widgets, theme extensions, tokens, and utilities already present in the repo.
- If the repo has an existing design system, reuse it instead of creating parallel widgets.
- If the repo does not have a suitable reusable widget, create one in a sensible shared location.

## Flutter rules

- Use null-safe Dart only.
- Prefer idiomatic Flutter widget trees over absolute positioning.
- Prefer `Row`, `Column`, `Wrap`, `Stack`, `Expanded`, `Flexible`, `Padding`, `Align`, `LayoutBuilder`, `ListView`, `CustomScrollView`, and slivers where appropriate.
- Use `Stack`/`Positioned` only for true overlays or layered compositions.
- Make sizing responsive; do not assume one screen width.
- Extract repeated sections into reusable widgets.
- Keep widget build methods readable; split complex sections into private widgets or separate files.

## Theming and tokens

- Do not hardcode colors, text styles, radii, spacing, shadows, or durations when they correspond to project tokens or theme values.
- Use existing `ThemeData`, `ColorScheme`, `TextTheme`, and any project `ThemeExtension`s.
- If missing tokens are required by the design, add them in the project’s established token/theme location instead of scattering literals through the widget tree.
- Keep light/dark behavior aligned with the project’s theme model.

## Typography

- Match font family, size, weight, height, letter spacing, and text alignment from Figma as closely as practical.
- Use existing text styles first; extend them only when necessary.
- Preserve intended line breaks, truncation, and max-line behavior.

## Layout fidelity

- Match padding, gaps, alignment, corner radii, borders, shadows, and hierarchy closely.
- Preserve component proportions unless small adjustments are needed for Flutter rendering or responsiveness.
- Respect Auto Layout intent from Figma when mapping to Flutter layout primitives.

## Assets

- Use assets provided by Figma/MCP when available.
- If the Figma payload provides image or SVG sources, use those assets directly.
- Do not add new icon libraries just to approximate assets already present in the design payload.
- Do not invent placeholder graphics if the asset exists in the payload.
- Store assets in the repo’s normal asset location and update `pubspec.yaml` if needed.
- Prefer SVG for vector assets when the payload provides it.

## Interactions

- Preserve visible interactive states represented in the design when practical.
- Wire obvious controls and callbacks using the project’s existing patterns.
- If business logic is unknown, stub behavior cleanly and note it.

## Accessibility

- Keep text readable and semantic.
- Ensure tap targets are reasonable.
- Preserve contrast and state clarity as much as the existing design allows.

## Output requirements

When completing the task:

1. List the files created or changed.
2. State which reusable widgets were introduced or reused.
3. State which assets were added.
4. Note any assumptions or unresolved ambiguities.
5. Highlight any places where the design required approximation.

## Anti-patterns

- Do not generate React, Tailwind, HTML, or CSS files for this task.
- Do not hardcode dozens of magic numbers if the repo has a token system.
- Do not flatten the whole screen into one giant widget when there are reusable patterns.
- Do not ignore screenshot verification.
- Do not replace unavailable assets with random substitutes.
