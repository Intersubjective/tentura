import 'package:tentura_server/domain/capability/capability_tag.dart';

bool isAllowedHelpType(String? helpType) =>
    helpType == null || helpType.isEmpty || kAllowedCapabilitySlugs.contains(helpType);
