import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/exception/baton_exceptions.dart';

Matcher isExpectedBatonPartnerInvalidException() =>
    isA<BatonPartnerInvalidException>();

Matcher isExpectedBatonNotPartnerException() =>
    isA<BatonNotPartnerException>();
