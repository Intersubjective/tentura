import 'package:tentura/domain/entity/profile.dart';

enum PersonPrimaryAction { none, trust, sendRequest }

enum PersonVisibilityState { neither, viewerOnly, subjectOnly, mutual }

/// Pure policy for person-profile primary and secondary actions (#100).
class PersonActionPolicy {
  PersonActionPolicy._({
    required this.viewerExplicitlyTrustsSubject,
    required this.subjectExplicitlyTrustsViewer,
    required this.viewerCanSeeSubject,
    required this.subjectCanSeeViewer,
    required this.visibilityState,
    required this.isMutuallyVisible,
    required this.canDirectSendRequest,
    required this.primaryAction,
    required this.showSecondaryTrust,
    required this.showRequestOptions,
  });

  factory PersonActionPolicy.from(
    Profile profile, {
    required bool isSelf,
    required bool isBlocked,
  }) {
    final viewerExplicitlyTrustsSubject = profile.viewerExplicitlyTrustsSubject;
    final subjectExplicitlyTrustsViewer = profile.subjectExplicitlyTrustsViewer;
    final viewerCanSeeSubject = profile.viewerCanSeeSubject;
    final subjectCanSeeViewer = profile.subjectCanSeeViewer;
    final isMutuallyVisible = profile.isMutuallyVisible;

    final visibilityState = _visibilityState(
      isMutuallyVisible: isMutuallyVisible,
      viewerCanSeeSubject: viewerCanSeeSubject,
      subjectCanSeeViewer: subjectCanSeeViewer,
    );

    if (isSelf || isBlocked) {
      return PersonActionPolicy._(
        viewerExplicitlyTrustsSubject: viewerExplicitlyTrustsSubject,
        subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
        viewerCanSeeSubject: viewerCanSeeSubject,
        subjectCanSeeViewer: subjectCanSeeViewer,
        visibilityState: visibilityState,
        isMutuallyVisible: isMutuallyVisible,
        canDirectSendRequest: false,
        primaryAction: PersonPrimaryAction.none,
        showSecondaryTrust: false,
        showRequestOptions: false,
      );
    }

    if (isMutuallyVisible) {
      return PersonActionPolicy._(
        viewerExplicitlyTrustsSubject: viewerExplicitlyTrustsSubject,
        subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
        viewerCanSeeSubject: viewerCanSeeSubject,
        subjectCanSeeViewer: subjectCanSeeViewer,
        visibilityState: visibilityState,
        isMutuallyVisible: true,
        canDirectSendRequest: true,
        primaryAction: PersonPrimaryAction.sendRequest,
        showSecondaryTrust: !viewerExplicitlyTrustsSubject,
        showRequestOptions: false,
      );
    }

    if (!viewerExplicitlyTrustsSubject) {
      return PersonActionPolicy._(
        viewerExplicitlyTrustsSubject: viewerExplicitlyTrustsSubject,
        subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
        viewerCanSeeSubject: viewerCanSeeSubject,
        subjectCanSeeViewer: subjectCanSeeViewer,
        visibilityState: visibilityState,
        isMutuallyVisible: false,
        canDirectSendRequest: false,
        primaryAction: PersonPrimaryAction.trust,
        showSecondaryTrust: false,
        showRequestOptions: true,
      );
    }

    return PersonActionPolicy._(
      viewerExplicitlyTrustsSubject: viewerExplicitlyTrustsSubject,
      subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
      viewerCanSeeSubject: viewerCanSeeSubject,
      subjectCanSeeViewer: subjectCanSeeViewer,
      visibilityState: visibilityState,
      isMutuallyVisible: false,
      canDirectSendRequest: false,
      primaryAction: PersonPrimaryAction.none,
      showSecondaryTrust: false,
      showRequestOptions: true,
    );
  }

  final bool viewerExplicitlyTrustsSubject;
  final bool subjectExplicitlyTrustsViewer;
  final bool viewerCanSeeSubject;
  final bool subjectCanSeeViewer;
  final PersonVisibilityState visibilityState;
  final bool isMutuallyVisible;
  final bool canDirectSendRequest;
  final PersonPrimaryAction primaryAction;
  final bool showSecondaryTrust;
  final bool showRequestOptions;

  static PersonVisibilityState _visibilityState({
    required bool isMutuallyVisible,
    required bool viewerCanSeeSubject,
    required bool subjectCanSeeViewer,
  }) {
    if (isMutuallyVisible) return PersonVisibilityState.mutual;
    if (viewerCanSeeSubject && !subjectCanSeeViewer) {
      return PersonVisibilityState.viewerOnly;
    }
    if (!viewerCanSeeSubject && subjectCanSeeViewer) {
      return PersonVisibilityState.subjectOnly;
    }
    return PersonVisibilityState.neither;
  }
}
