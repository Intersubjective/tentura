import 'package:tentura_server/domain/capability/capability_tag.dart';

export 'package:tentura_root/consts.dart'
    show kMaxHelpOfferHelpTypes, kMaxHelpOfferRoleLabelLength;

bool isAllowedHelpType(String? helpType) =>
    helpType == null || helpType.isEmpty || kAllowedCapabilitySlugs.contains(helpType);
