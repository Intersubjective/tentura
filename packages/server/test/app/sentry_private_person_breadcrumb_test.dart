import 'dart:convert';

import 'package:sentry/sentry.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_init.dart';
import 'package:tentura_server/env.dart';

void main() {
  const operations = [
    'phantomCreate',
    'phantomUpdate',
    'phantomDelete',
    'phantomInviteEnsure',
    'phantomInviteRotate',
    'phantomLink',
    'phantomUnmerge',
    'phantomHintDismiss',
  ];

  group('Sentry breadcrumbs for private people on the Field', () {
    setUpAll(() async {
      addTearDown(Sentry.close);
      await initSentry(
        env: Env(
          sentryDsn: 'https://public@example.invalid/1',
          sentryTracesSampleRate: 0,
          printEnv: false,
        ),
        appRunner: () {},
      );
    });

    for (final operation in operations) {
      test('$operation keeps private variables out of telemetry', () async {
        const name = 'PrivateBreadcrumbName731';
        const id = 'PHb7eadc000001';
        const control = 'ordinaryGraphqlOperation';
        const category = 'graphql';
        await Sentry.configureScope((scope) => scope.clearBreadcrumbs());
        await Sentry.addBreadcrumb(
          Breadcrumb(category: category, message: control),
        );
        final variables = {'name': name, 'phantomId': id};
        await Sentry.addBreadcrumb(
          Breadcrumb(
            category: category,
            message: '$operation variables=${jsonEncode(variables)}',
            data: {'operationName': operation, 'variables': variables},
          ),
        );

        late List<Breadcrumb> breadcrumbs;
        await Sentry.configureScope((scope) {
          breadcrumbs = scope.breadcrumbs;
        });
        expect(breadcrumbs.map((crumb) => crumb.message), contains(control));
        final wire = jsonEncode([
          for (final crumb in breadcrumbs)
            {'message': crumb.message, 'data': crumb.data},
        ]);
        expect(wire, allOf(isNot(contains(name)), isNot(contains(id))));
      });
    }
  });
}
