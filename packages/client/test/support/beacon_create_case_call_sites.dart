import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

const beaconCreateConstructor = 'BeaconCreateCase';
const beaconCreateFactory = 'buildBeaconCreateCase';
const beaconCreateLegacyHelper = 'fakeBeaconCreateCase';

typedef BeaconCreateCall = ({
  String target,
  String context,
  int offset,
  int line,
  Map<String, String> ports,
});

Iterable<BeaconCreateCall> beaconCreateCalls(String source, String path) {
  if (!source.contains(beaconCreateConstructor)) return const [];
  final parsed = parseString(content: source, path: path);
  final collector = _CallCollector(parsed.lineInfo.getLocation);
  parsed.unit.accept(collector);
  return collector.calls;
}

class _CallCollector extends RecursiveAstVisitor<void> {
  _CallCollector(this._location);

  final CharacterLocation Function(int) _location;
  final calls = <BeaconCreateCall>[];

  void _record(Token name, AstNode node, ArgumentList argumentList) {
    final target = name.lexeme;
    final parents = <String>[];
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      switch (parent) {
        case VariableDeclaration(:final name):
          parents.add(name.lexeme);
        case NamedArgument(:final name):
          parents.add(name.lexeme);
        case FunctionDeclaration(:final name):
          parents.add(name.lexeme);
        case MethodDeclaration(:final name):
          parents.add(name.lexeme);
        case MethodInvocation(
          methodName: SimpleIdentifier(
            name: 'group' || 'test' || 'testWidgets' || 'blocTest',
          ),
        ):
          final arguments = parent.argumentList.arguments;
          if (arguments.isNotEmpty && arguments.first is StringLiteral) {
            parents.add(arguments.first.toSource());
          }
      }
    }
    final arguments = argumentList.arguments;
    final ports = target == beaconCreateConstructor
        ? {
            if (arguments.isNotEmpty)
              'beacons': arguments[0].argumentExpression.toSource(),
            if (arguments.length > 1)
              'images': arguments[1].argumentExpression.toSource(),
          }
        : {
            for (final argument in arguments.whereType<NamedArgument>())
              if (target == beaconCreateLegacyHelper &&
                  argument.name.lexeme == 'write')
                'beacons': argument.argumentExpression.toSource()
              else
                argument.name.lexeme: argument.argumentExpression.toSource(),
          };
    calls.add((
      target: target,
      context: parents.reversed.join(' / '),
      offset: name.offset,
      line: _location(name.offset).lineNumber,
      ports: ports,
    ));
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name;
    if (name.lexeme == beaconCreateConstructor) {
      _record(name, node, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // An implicit constructor invocation can parse as a method call before
    // Dart has resolved the receiver and imports.
    final name = node.methodName.token;
    if (name.lexeme == beaconCreateConstructor ||
        name.lexeme == beaconCreateFactory ||
        name.lexeme == beaconCreateLegacyHelper) {
      _record(name, node, node.argumentList);
    } else if (name.lexeme == 'new') {
      final receiver = node.target?.endToken;
      if (receiver != null && receiver.lexeme == beaconCreateConstructor) {
        _record(receiver, node, node.argumentList);
      }
    }
    super.visitMethodInvocation(node);
  }
}
