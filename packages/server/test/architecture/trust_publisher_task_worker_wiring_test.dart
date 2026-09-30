// The analyzer is only reachable transitively; this is a test-only AST check.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/task_worker_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

class _Tasks implements TaskRepositoryPort {
  @override
  Future<T?> acquire<T extends TaskEntity>() async => null;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Images implements ImageRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Outbox implements NotificationOutboxRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Digest implements EmailDigestCase {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _CountingPort implements TrustPublishPort {
  int cutoverChecks = 0;

  @override
  Future<bool> cutoverPending() async {
    cutoverChecks++;
    return true; // stop the run right after the gate
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Env _env() => Env(
  environment: Environment.test,
  publicOrigin: 'https://t.example',
  unsubscribeSigningSecret: 'secret',
  taskOnEmptyDelay: const Duration(milliseconds: 1),
);

TaskWorkerCase _worker(TrustPublisherCase publisher) => TaskWorkerCase(
  _Images(),
  _Tasks(),
  _Digest(),
  _Outbox(),
  trustPublisher: publisher,
  env: _env(),
  logger: Logger('test'),
);

class _FindCreate extends RecursiveAstVisitor<void> {
  MethodDeclaration? create;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'create' && node.isStatic) create = node;
    super.visitMethodDeclaration(node);
  }
}

// Unresolved parse: `TaskWorkerCase(...)` is a MethodInvocation, `new`/`const`
// forms are InstanceCreationExpression; accept both.
class _FindWorkerCall extends RecursiveAstVisitor<void> {
  final argumentLists = <ArgumentList>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'TaskWorkerCase') {
      argumentLists.add(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'TaskWorkerCase') {
      argumentLists.add(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

class _FindPublisherTask extends RecursiveAstVisitor<void> {
  final closures = <FunctionExpression>[];

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final src = node.body.toSource();
    final inner = closures.any((c) => node.offset >= c.offset && node.end <= c.end);
    if (!inner && src.contains('_trustPublisher') && src.contains('Duration(')) {
      closures.add(node);
      return;
    }
    super.visitFunctionExpression(node);
  }
}

class _DurationFinder extends RecursiveAstVisitor<void> {
  final found = <String>{};

  void _collect(ArgumentList args) {
    for (final a in args.arguments.whereType<NamedArgument>()) {
      found.add('${a.name.lexeme}:${a.argumentExpression}');
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'Duration') {
      _collect(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'Duration') {
      _collect(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  group('TaskWorkerCase.create (production factory)', () {
    late MethodDeclaration create;

    setUpAll(() {
      final unit = parseString(
        content: File(
          'lib/domain/use_case/task_worker_case.dart',
        ).readAsStringSync(),
      ).unit;
      final finder = _FindCreate();
      unit.accept(finder);
      create = finder.create!;
    });

    test('takes the publisher as a parameter and forwards exactly that', () {
      final param = create.parameters!.parameters
          .whereType<RegularFormalParameter>()
          .where((p) => p.type.toString() == 'TrustPublisherCase')
          .toList();
      expect(param, hasLength(1), reason: 'non-nullable TrustPublisherCase');

      final calls = _FindWorkerCall();
      create.body.accept(calls);
      expect(calls.argumentLists, hasLength(1));
      final forwarded = calls.argumentLists.single.arguments
          .whereType<NamedArgument>()
          .where((e) => e.name.lexeme == 'trustPublisher')
          .toList();
      expect(forwarded, hasLength(1));
      expect(forwarded.single.argumentExpression, isA<SimpleIdentifier>());
      expect(
        (forwarded.single.argumentExpression as SimpleIdentifier).name,
        param.single.name!.lexeme,
      );
    });
  });

  group('production DI registration', () {
    late List<Annotation> publisherAnnotations;
    late List<Annotation> portImplAnnotations;

    setUpAll(() {
      publisherAnnotations = [];
      portImplAnnotations = [];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('.config.dart'));
      for (final f in files) {
        final unit = parseString(
          content: f.readAsStringSync(),
          throwIfDiagnostics: false,
        ).unit;
        for (final d in unit.declarations.whereType<ClassDeclaration>()) {
          final name = d.namePart.typeName.lexeme;
          if (name == 'TrustPublisherCase') {
            publisherAnnotations.addAll(d.metadata);
          }
          final implementsPort =
              d.implementsClause?.interfaces.any(
                (t) => t.name.lexeme == 'TrustPublishPort',
              ) ??
              false;
          if (implementsPort) portImplAnnotations.addAll(d.metadata);
        }
      }
    });

    test('TrustPublisherCase is an injectable registration', () {
      final names = publisherAnnotations.map((a) => a.name.name).toSet();
      expect(
        names.intersection({'Singleton', 'LazySingleton', 'Injectable'}),
        isNotEmpty,
      );
    });

    test('TrustPublishPort is registered for dev, prod and test', () {
      final registrations = portImplAnnotations
          .where((a) => a.arguments.toString().contains('as: TrustPublishPort'))
          .map((a) => a.arguments.toString())
          .toList();
      expect(registrations, isNotEmpty);
      final all = registrations.join();
      expect(all, contains('Environment.dev'));
      expect(all, contains('Environment.prod'));
      expect(all, contains('Environment.test'));
    });
  });

  group('TaskWorkerCase publisher job', () {
    test('the job is gated by a 10 s Duration in _tasks', () {
      final unit = parseString(
        content: File(
          'lib/domain/use_case/task_worker_case.dart',
        ).readAsStringSync(),
      ).unit;
      final finder = _FindPublisherTask();
      unit.accept(finder);
      expect(finder.closures, hasLength(1));
      final durations = _DurationFinder();
      finder.closures.single.accept(durations);
      expect(durations.found, contains('seconds:10'));
    });

    test('runs at tick cadence of 10 s: once in the first moments', () async {
      final port = _CountingPort();
      final worker = _worker(
        TrustPublisherCase(port, env: _env(), logger: Logger('test')),
      );

      unawaited(worker.run());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await worker.dispose();

      expect(port.cutoverChecks, 1);
    });

    test('nudge makes the next worker tick run the publisher again', () async {
      final port = _CountingPort();
      final publisher = TrustPublisherCase(
        port,
        env: _env(),
        logger: Logger('test'),
      );
      final worker = _worker(publisher);

      unawaited(worker.run());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(port.cutoverChecks, 1);

      publisher.nudge();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await worker.dispose();

      expect(port.cutoverChecks, 2);
    });
  });
}
