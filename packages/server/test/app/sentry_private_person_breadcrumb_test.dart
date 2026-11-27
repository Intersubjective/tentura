import 'dart:convert';

import 'package:sentry/sentry.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_init.dart';
import 'package:tentura_server/env.dart';

void main() {
  const operations = [
    'phantomCreate',
    'phantomCreateBatch',
    'PhantomCreateBatch',
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
      expect(Sentry.isEnabled, isTrue);
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
    for (final operation in [
      'personNote',
      'personNoteSearch',
      'personNoteUpsert',
      'personNoteDelete',
    ]) {
      test('$operation keeps note text out of breadcrumbs', () async {
        const body = 'PrivateNoteBreadcrumbBody731';
        const query = 'PrivateNoteBreadcrumbQuery846';
        final control = Breadcrumb(
          category: 'graphql',
          message: 'ordinaryGraphqlOperation',
          data: {'operationName': 'ordinaryGraphqlOperation', 'count': 2},
        );
        await Sentry.configureScope((scope) => scope.clearBreadcrumbs());
        await Sentry.addBreadcrumb(control);

        final variables = {'body': body, 'q': query};
        await Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'graphql',
            message: '$operation variables=${jsonEncode(variables)}',
            data: {'operationName': operation, 'variables': variables},
          ),
        );

        late List<Breadcrumb> breadcrumbs;
        await Sentry.configureScope((scope) {
          breadcrumbs = scope.breadcrumbs;
        });
        final payloads = breadcrumbs.map((crumb) => crumb.toJson()).toList();
        expect(payloads, contains(equals(control.toJson())));
        expect(
          jsonEncode(payloads),
          isNot(anyOf(contains(body), contains(query))),
        );
      });
    }
  });
}
