import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/semantics_free_tooltip.dart';

import '../../domain/constellation_people.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_camera_controls.dart';

/// Most people a name search lists at once; typing narrows it further.
const kConstellationPersonSearchLimit = 200;

/// The map's name search (#253): finds a person on the field and centres the
/// map on them, selected for two seconds (highlighted, with their panel open).
class ConstellationPersonSearchButton extends StatelessWidget {
  const ConstellationPersonSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ConstellationCubit>();
    return SearchAnchor(
      viewHintText: l10n.constellationSearchHint,
      // The icon names the button; the hover tooltip adds no second name
      // (#678).
      builder: (context, controller) => SemanticsFreeTooltip(
        message: l10n.constellationSearchPeople,
        child: IconButton(
          key: const Key('constellation.app_bar.search'),
          icon: Icon(
            Icons.person_search_outlined,
            semanticLabel: l10n.constellationSearchPeople,
          ),
          constraints: BoxConstraints(
            minWidth: tt.buttonHeight,
            minHeight: tt.buttonHeight,
          ),
          onPressed: controller.openView,
        ),
      ),
      suggestionsBuilder: (viewContext, controller) {
        final matches = [
          for (final person in cubit.fieldPeople)
            if (!person.isViewer &&
                constellationPersonMatches(person, controller.text))
              person,
        ];
        if (matches.isEmpty) {
          return [
            ListTile(
              key: const Key('constellation.search.no_match'),
              title: Text(l10n.constellationSearchNoMatch),
            ),
          ];
        }
        return [
          for (final person in matches.take(kConstellationPersonSearchLimit))
            _PersonSuggestion(
              person: person,
              // The search view is its own route, outside the cubit's scope.
              profile: cubit.profileForPersonId(person.id),
              onTap: () {
                controller.closeView(null);
                // After the search view's route has gone, so the panel and
                // the camera use the field's own viewport.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  cubit.focusPerson(
                    person.id,
                    insets: ConstellationCameraControls.cameraViewportInsets(
                      context,
                      contextPanelVisible: true,
                    ),
                  );
                });
              },
            ),
        ];
      },
    );
  }
}

class _PersonSuggestion extends StatelessWidget {
  const _PersonSuggestion({
    required this.person,
    required this.profile,
    required this.onTap,
  });

  final ConstellationFieldPerson person;
  final Profile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    return ListTile(
      key: Key('constellation.search.person.${person.id}'),
      leading: profile == null ? null : TenturaAvatar.small(profile: profile),
      title: Text(person.name, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
