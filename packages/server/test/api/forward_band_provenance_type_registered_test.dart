import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';

void main() {
  test('ForwardRecipientBandProvenanceInput is registered and resolvable', () {
    final types = customTypes;
    expect(
      types.any(
        (t) => identical(t, InputFieldForwardRecipientBandProvenance.type),
      ),
      isTrue,
    );
    expect(
      resolveStitchedV2Type('v2_ForwardRecipientBandProvenanceInput', types),
      same(InputFieldForwardRecipientBandProvenance.type),
    );
  });
}
