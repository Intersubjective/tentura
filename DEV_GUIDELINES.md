# Development guidelines

Project-specific conventions beyond what lives in `.cursor/rules/`.

## Initial load on detail and list screens (spinner)

When a screen’s cubit loads data asynchronously after navigation, the first frame must not paint “success” UI built from empty or placeholder domain objects (that causes wrong actions, empty titles, and layout flashes).

**Do this:**

1. **State** — Start with `status: StateStatus.isLoading` (or equivalent) until the first fetch completes. Do not default to `StateIsSuccess()` while `beacon`, `author`, or similar fields are still placeholders.
2. **Body** — Use `BlocBuilder` with `buildWhen: (_, c) => c.isSuccess || c.isLoading` (or a superset that includes loading when the UI must react). When `state.isLoading`, show:

   ```dart
   const Center(
     child: CircularProgressIndicator.adaptive(),
   )
   ```

3. **Consistency** — Follow the same pattern as `InboxScreen`, `MyFieldScreen`, `MyWorkScreen`, `RatingScreen`, and `BeaconViewScreen`. A thin linear progress indicator under the app bar can supplement this for in-place reloads; it is not a substitute for hiding bogus content on the **initial** load.

**Rationale:** A centered adaptive progress indicator is the project default for “data not ready yet.” It avoids rendering ownership-specific controls (e.g. Commit vs owner actions) against `Profile()` / empty ids.
