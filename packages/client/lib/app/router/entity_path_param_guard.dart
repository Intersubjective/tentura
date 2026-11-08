/// Rejects URL segments that are still AutoRoute path templates (`:id`).
bool isSubstitutedEntityIdPathParam(String id) =>
    id.isNotEmpty && id != ':id' && !id.startsWith(':');
