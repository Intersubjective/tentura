import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState, Tristate;

import 'package:auto_route/auto_route.dart';
import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart'
    show AuthRequestIntentSignUp;
import 'package:tentura/data/service/remote_api_client/auth_box.dart';
import 'package:tentura/data/service/remote_api_client/auth_remote_client.dart';
import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_client/session_fetch.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/gql/_g/sign_up.data.gql.dart';
import 'package:tentura/features/auth/data/gql/_g/sign_up.req.gql.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/bloc/register_invite_cubit.dart';
import 'package:tentura/features/auth/ui/screen/auth_register_screen.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/port/invitation_accept_port.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import 'auth_test_helpers.dart';

const _inviteCode = 'I806d29daebbe';
const _displayName = 'Ada Lovelace';
const _handle = 'ada_lovelace';
const _authRequestToken = 'signup-auth-request';
const _newAccountId = 'U000000000001';
const _env = Env(needInviteCode: true);

void main() {
  for (final (language, yes, no) in [
    ('en', 'Yes', 'No'),
    ('ru', 'Да', 'Нет'),
  ]) {
    final locale = Locale(language);
    final l10n = lookupL10n(locale);

    testWidgets(
      'Registration offers unanswered email discoverability choices in $language',
      (
        tester,
      ) async {
        await _openRegisterScreen(tester, locale);

        final title = find.text(l10n.settingsEmailDiscoverability);
        expect(title, findsOneWidget);
        if (language == 'en') {
          expect(
            l10n.settingsEmailDiscoverability,
            "People who have my email can see I'm on Tentura",
          );
        } else {
          expect(
            l10n.settingsEmailDiscoverability,
            matches(RegExp('[А-Яа-я]')),
          );
        }

        for (final label in [yes, no]) {
          final option = find.text(label);
          expect(option, findsOneWidget);
          await tester.ensureVisible(option);
          await tester.pumpAndSettle();
          expect(option.hitTestable(), findsOneWidget);
          final flags = tester
              .getSemantics(option)
              .getSemanticsData()
              .flagsCollection;
          expect(flags.isChecked, isNot(CheckedState.isTrue));
          expect(flags.isSelected, isNot(Tristate.isTrue));
          expect(
            flags.isChecked == CheckedState.isFalse ||
                flags.isSelected == Tristate.isFalse,
            isTrue,
            reason: '$label is exposed as an unselected choice',
          );
        }
        final english = _catalog('en');
        final russian = _catalog('ru');
        expect(
          english.entries
              .where((entry) => entry.value == 'Yes')
              .map(
                (entry) => russian[entry.key],
              ),
          contains('Да'),
        );
        expect(
          english.entries
              .where((entry) => entry.value == 'No')
              .map(
                (entry) => russian[entry.key],
              ),
          contains('Нет'),
        );
        _expectPublicCopy(tester);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Registration stays open and asks for an email discoverability choice in $language',
      (
        tester,
      ) async {
        final auth = _SignupObserver();
        await _openRegisterScreen(tester, locale, authOverride: auth);
        await _fillRegistration(tester, l10n);
        final beforeSubmit = _screenText(tester).toSet();

        await _createAccount(tester, l10n);

        expect(auth.signupCalls, 0, reason: 'Do not start signup');
        expect(find.byType(AuthRegisterScreen), findsOneWidget);

        final choose = RegExp(
          language == 'en'
              ? 'choose|select|answer|pick'
              : 'выбер|выбор|укаж|ответ',
          caseSensitive: false,
        );
        final validation = _screenText(tester).where(
          (text) => !beforeSubmit.contains(text) && choose.hasMatch(text),
        );
        expect(
          validation,
          hasLength(1),
          reason: 'Explain which choice is missing',
        );
        final message = validation.single;
        _expectTranslatedValidation(language, message);
        final errorCenter = tester.getCenter(find.text(message));
        final options = [yes, no].map(
          (label) => tester.getCenter(find.text(label)),
        );
        expect(
          options.any((center) => (center.dy - errorCenter.dy).abs() < 96),
          isTrue,
          reason: 'Show the validation message by the discoverability choices',
        );
        _expectPublicCopy(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (answer, discoverability) in [('Yes', true), ('No', false)]) {
    testWidgets(
      'Registration sends $answer to the signup API with the invite, name and handle',
      (
        tester,
      ) async {
        const locale = Locale('en');
        final l10n = lookupL10n(locale);
        final (cubit, transport) = await _openRegisterScreen(tester, locale);
        await _fillRegistration(tester, l10n);
        final option = find.text(answer);
        expect(
          option,
          findsOneWidget,
          reason: 'Registration must offer $answer',
        );
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();

        await _createAccount(tester, l10n);

        expect(transport.inviteCodes, [_inviteCode]);
        expect(transport.signupVariables, hasLength(1));
        expect(
          transport.signupVariables.single,
          containsPair('authRequestToken', _authRequestToken),
        );
        expect(
          transport.signupVariables.single,
          containsPair('displayName', _displayName),
        );
        expect(
          transport.signupVariables.single,
          containsPair('handle', _handle),
        );
        expect(
          transport.signupVariables.single,
          containsPair('discoverability', discoverability),
        );
        expect(cubit.state.currentAccountId, _newAccountId);
      },
    );
  }
}

Future<(AuthCubit, _SignupTransport)> _openRegisterScreen(
  WidgetTester tester,
  Locale locale, {
  AuthCubit? authOverride,
}) async {
  await usePhoneSurface(tester);
  final gl = GetIt.I;
  await gl.reset();
  addTearDown(gl.reset);
  final transport = _SignupTransport();
  final remote = AuthRemoteRepository(
    remoteApiService: transport,
    log: Logger('register-test'),
  );
  final local = EmptyAuthLocal();
  final profiles = _UnusedProfiles();
  final effects = UiEffectBus();
  final cubit =
      authOverride ??
      await AuthCubit.hydrated(
        _env,
        buildTestAuthCase(local, remote),
        AccountCase(
          local,
          remote,
          _EmptyClipboard(),
          profiles,
          env: _env,
          logger: Logger('register-test'),
        ),
        profiles,
        effects,
      );
  gl
    ..registerSingleton<Env>(_env)
    ..registerSingleton<AuthCubit>(cubit, dispose: (auth) => auth.dispose())
    ..registerFactory<RegisterInviteCubit>(
      () => RegisterInviteCubit.withPort(_AvailableInvite(), effects: effects),
    );

  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'Register',
        path: '/',
        builder: (context, _) =>
            const AuthRegisterScreen().wrappedRoute(context),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router.config(),
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AuthRegisterScreen), findsOneWidget);
  return (cubit, transport);
}

Future<void> _fillRegistration(WidgetTester tester, L10n l10n) async {
  for (final (label, value) in [
    (l10n.labelInvitationCode, _inviteCode),
    (l10n.labelDisplayName, _displayName),
    (l10n.labelUserHandle, _handle),
  ]) {
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }
}

Future<void> _createAccount(WidgetTester tester, L10n l10n) async {
  final create = find.text(l10n.buttonCreate);
  await tester.ensureVisible(create);
  await tester.tap(create);
  await tester.pumpAndSettle();
}

Iterable<String> _screenText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AuthRegisterScreen),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '');

void _expectPublicCopy(WidgetTester tester) {
  expect(
    _screenText(tester).join(' '),
    isNot(contains(RegExp('phantom', caseSensitive: false))),
  );
}

Map<String, dynamic> _catalog(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void _expectTranslatedValidation(String language, String message) {
  final translated = _catalog(language).entries.where(
    (entry) => !entry.key.startsWith('@') && entry.value == message,
  );
  expect(translated, isNotEmpty, reason: 'Use a localized validation message');
  final otherLanguage = language == 'en' ? 'ru' : 'en';
  final otherCatalog = _catalog(otherLanguage);
  expect(
    translated.map((entry) => otherCatalog[entry.key]),
    contains(
      allOf(
        isA<String>(),
        isNot(message),
        matches(language == 'en' ? RegExp('[А-Яа-я]') : RegExp('[A-Za-z]')),
        isNot(contains(RegExp('phantom', caseSensitive: false))),
      ),
    ),
  );
}

final class _SignupObserver extends Fake implements AuthCubit {
  int signupCalls = 0;

  @override
  final state = AuthState(updatedAt: DateTime(2026));

  @override
  Stream<AuthState> get stream => const Stream.empty();

  @override
  bool get isClosed => false;

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getInvitationCodeFromClipboard({
    bool supressError = false,
  }) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #signUp) {
      signupCalls++;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

final class _SignupTransport extends Fake implements AuthRemoteClient {
  final inviteCodes = <String>[];
  final signupVariables = <Map<String, dynamic>>[];

  @override
  Future<void> dropAuth() async {}

  @override
  Future<void> setSessionAuth() async {}

  @override
  Future<Credentials> getAuthToken() async => throw SessionHttpException(401);

  @override
  Future<bool> clearSessionCookie() async => true;

  @override
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    if (returnAuthRequestToken case AuthRequestIntentSignUp(
      :final invitationCode,
    )) {
      inviteCodes.add(invitationCode);
    }
    return _authRequestToken;
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is! GSignUpReq) {
      throw UnsupportedError(
        'Unexpected auth request: ${request.operation.operationName}',
      );
    }
    signupVariables.add(request.varsToJson());
    final data = GSignUpData(
      (builder) => builder.signUp.subject = _newAccountId,
    );
    return Stream.value(
      OperationResponse<TData, TVars>(
        operationRequest: request,
        dataSource: DataSource.Link,
        data: data as TData,
      ),
    );
  }

  @override
  Future<void> bindRealtimeAccount(String accountId) async {}
}

final class _UnusedProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}

final class _EmptyClipboard extends Fake implements PlatformRepositoryPort {
  @override
  Future<String> getStringFromClipboard() async => '';
}

final class _AvailableInvite extends Fake implements InvitationAcceptPort {
  @override
  Future<InvitePreview> fetchInvitePreview(String code) async =>
      const InvitePreview(
        codeStatus: InviteCodeStatus.available,
        callerStatus: InviteCallerStatus.anonymous,
      );
}
