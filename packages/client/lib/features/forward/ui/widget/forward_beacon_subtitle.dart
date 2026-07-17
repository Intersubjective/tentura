import 'package:tentura/ui/l10n/l10n.dart';

String forwardBeaconSubtitle({
  required L10n l10n,
  required String beaconTitle,
  required String lifecycleLabel,
}) {
  if (beaconTitle.isEmpty) {
    return lifecycleLabel;
  }
  return '$beaconTitle · $lifecycleLabel';
}
