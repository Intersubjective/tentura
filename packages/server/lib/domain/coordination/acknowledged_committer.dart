import 'package:tentura_server/domain/coordination/coordination_response_type.dart';

/// Author acknowledged this help offer (`useful` or `needCoordination`).
bool isAcknowledgedCommitterResponse(int? responseType) =>
    responseType == CoordinationResponseType.useful.smallintValue ||
    responseType == CoordinationResponseType.needCoordination.smallintValue;
