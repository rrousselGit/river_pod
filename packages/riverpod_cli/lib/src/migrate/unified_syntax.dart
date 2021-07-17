import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:codemod/codemod.dart';
import 'package:pub_semver/pub_semver.dart';
// ignore_for_file: avoid_print

enum ClassType { consumer, hook, stateless, stateful, none }
enum ProviderType {
  stream,
  future,
  plain,
  state,
  statenotifier,
  changenotifier,
  none
}

/// Aggregates information needed for the unified syntax change with hooks
///
/// Runs before [RiverpodUnifiedSyntaxChangesMigrationSuggestor]
class RiverpodHooksProviderInfo extends GeneralizingAstVisitor<void>
    with AstVisitingSuggestor {
  RiverpodHooksProviderInfo(this.riverpodVersion);
  final VersionConstraint riverpodVersion;
  static Map<String, bool> isConsumerHookFunction = {};
  static Map<String, Set<String>> hookDependencies = {};
  FunctionDeclaration? currentFunction;
  static bool computedDependencies = false;

  static bool shouldMigrate(String functionName) {
    _propagateDependencies();
    return isConsumerHookFunction[functionName] ?? false;
  }

  static void _propagateDependencies() {
    if (computedDependencies) {
      return;
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in isConsumerHookFunction.entries) {
        if (entry.value) {
          for (final dependency in hookDependencies.entries) {
            if (dependency.value.contains(entry.key) &&
                !isConsumerHookFunction[dependency.key]!) {
              isConsumerHookFunction[dependency.key] = true;
              changed = true;
            }
          }
        }
      }
    }
    computedDependencies = true;
  }

  @override
  bool shouldResolveAst(FileContext context) => true;

  @override
  bool shouldSkip(FileContext context) {
    return riverpodVersion.allowsAny(
      VersionConstraint.parse('^1.0.0-dev.0'),
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    currentFunction = node;
    isConsumerHookFunction[currentFunction!.name.name] = false;
    hookDependencies[currentFunction!.name.name] = {};
    super.visitFunctionDeclaration(node);
    currentFunction = null;
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final functionName = node.function.toSource();
    if (functionName.startsWith('use') && currentFunction != null) {
      hookDependencies[currentFunction!.name.name]!.add(functionName);
      if (functionName == 'useProvider') {
        isConsumerHookFunction[currentFunction!.name.name] = true;
      }
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final functionName = node.methodName.toSource();
    if (currentFunction != null) {
      if (functionName.startsWith('use')) {
        hookDependencies[currentFunction!.name.name]!.add(functionName);
        if (functionName == 'useProvider') {
          hookDependencies[currentFunction!.name.name]!.add(functionName);
          isConsumerHookFunction[currentFunction!.name.name] = true;
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// A suggestor that yields changes to notifier changes
class RiverpodUnifiedSyntaxChangesMigrationSuggestor
    extends GeneralizingAstVisitor<void> with AstVisitingSuggestor {
  RiverpodUnifiedSyntaxChangesMigrationSuggestor(this.riverpodVersion);

  final VersionConstraint riverpodVersion;

  @override
  bool shouldSkip(FileContext context) {
    return riverpodVersion.allowsAny(
      VersionConstraint.parse('^1.0.0-dev.0'),
    );
  }

  @override
  bool shouldResolveAst(FileContext context) => true;

  ClassType withinClass = ClassType.none;
  ClassDeclaration? classDeclaration;
  FormalParameterList? params;
  FunctionBody? functionBody;
  ConstructorName? hookBuilder;
  bool inConsumerBuilder = false;
  bool inHookBuilder = false;
  bool lookingForParams = false;
  final Map<String, ClassDeclaration> statefulDeclarations = {};
  final Set<String> statefulNeedsMigration = {};
  final Map<String, FunctionDeclaration> functionDecls = {};
  final Map<String, MethodDeclaration> methodDecls = {};
  final Set<String> functionNeedsMigration = {};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    methodDecls.clear();
    final name = node.extendsClause?.superclass.name.name;
    classDeclaration = node;
    if (name == 'StatelessWidget') {
      withinClass = ClassType.stateless;
    } else if (name == 'State') {
      withinClass = ClassType.stateful;
    } else if (name == 'ConsumerWidget') {
      withinClass = ClassType.consumer;
    } else if (name == 'HookWidget') {
      withinClass = ClassType.hook;
    } else {
      withinClass = ClassType.none;
      classDeclaration = null;
    }
    if (name == 'StatefulWidget') {
      statefulDeclarations[node.name.name] = node;
      if (statefulNeedsMigration.contains(node.name.name)) {
        migrateStateful(node.name.name);
      }
    }
    super.visitClassDeclaration(node);
    withinClass = ClassType.none;
    classDeclaration = null;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.name == 'build') {
      params = node.parameters;
      functionBody = node.body;
      if (withinClass == ClassType.consumer) {
        // Consumer should be migrated regardless if providers are watched / read or not
        migrateParams();
      }
    } else if (node.name.name == 'didUpdateProvider') {
      yieldPatch(
          ', ProviderContainer container',
          node.parameters!.parameters.last.end,
          node.parameters!.parameters.last.end);
      yieldPatch(', Object? oldValue, ', node.parameters!.parameters.first.end,
          node.parameters!.parameters.last.offset);
    }
    methodDecls[node.name.name] = node;
    migrateOnChangeFunction(node.name.name);
    super.visitMethodDeclaration(node);
  }

  void migrateParams() {
    try {
      if (withinClass == ClassType.none) {
        return;
      }
      final params = this.params;
      if (params != null) {
        if (inConsumerBuilder) {
          assert(
            params.parameters.length == 3,
            'Consumers should have a parameter list of length 3',
          );
          yieldPatch(
            'ref',
            params.parameters[1].offset,
            params.parameters[1].end,
          );
        } else if (inHookBuilder) {
          assert(
            params.parameters.length == 1,
            'HookBuilders should have a parameter list of length 1, $params',
          );
          yieldPatch('HookConsumer', hookBuilder!.offset, hookBuilder!.end);
          yieldPatch(
            ', ref, child',
            params.parameters.first.end,
            params.parameters.first.end,
          );
        } else if (withinClass != ClassType.stateful) {
          // In build method
          if (params.parameters.length == 2) {
            // Consumer
            yieldPatch(
              'WidgetRef ref',
              params.parameters.last.offset,
              params.parameters.last.end,
            );
          }
          if (params.parameters.length == 1) {
            // Stateless, Hook
            yieldPatch(
              ', WidgetRef ref',
              params.parameters.last.end,
              params.parameters.last.end,
            );
          }
        }
      }
    } catch (e, st) {
      print(
          'Error in migration tool while migrating widget build method parameters $params\n$e\n$st');
    }

    params = null;
  }

  void migrateClass() {
    final classDecl = classDeclaration;

    try {
      if (classDecl != null && !inHookBuilder && !inConsumerBuilder) {
        if (withinClass == ClassType.hook) {
          yieldPatch(
            'HookConsumerWidget',
            classDecl.extendsClause!.superclass.offset,
            classDecl.extendsClause!.superclass.end,
          );
        } else if (withinClass == ClassType.stateless) {
          yieldPatch(
            'ConsumerWidget',
            classDecl.extendsClause!.superclass.offset,
            classDecl.extendsClause!.superclass.end,
          );
        } else if (withinClass == ClassType.stateful) {
          yieldPatch(
            'ConsumerState',
            classDecl.extendsClause!.superclass.name.offset,
            classDecl.extendsClause!.superclass.name.end,
          );

          migrateStateful(classDecl
              .extendsClause!.superclass.typeArguments!.arguments.first.type!
              .getDisplayString(withNullability: true));
        }
      }
    } catch (e, st) {
      print(
          'Error in migration tool while migrating class $classDecl\n$e\n$st');
    }
    classDeclaration = null;
  }

  void migrateConsumerHookFunctionCall(ArgumentList argumentList) {
    try {
      if (argumentList.arguments.isNotEmpty) {
        yieldPatch('ref, ', argumentList.arguments.first.offset,
            argumentList.arguments.first.offset);
      } else {
        yieldPatch('ref', argumentList.leftParenthesis.end,
            argumentList.rightParenthesis.offset);
      }
    } catch (e, st) {
      print(
          'Error in migration tool while migrating consumer hook function call $argumentList\n$e\n$st');
    }
  }

  void migrateFunctionDeclaration(FunctionDeclaration node) {
    try {
      if (node.functionExpression.parameters!.parameters.isNotEmpty) {
        yieldPatch(
            'WidgetRef ref, ',
            node.functionExpression.parameters!.parameters.first.offset,
            node.functionExpression.parameters!.parameters.first.offset);
      } else {
        yieldPatch(
            'WidgetRef ref',
            node.functionExpression.parameters!.leftParenthesis.end,
            node.functionExpression.parameters!.rightParenthesis.offset);
      }
      functionDecls[node.name.name] = node;
    } catch (e, st) {
      print(
          'Error in migration tool while migrating function declaration $node\n$e\n$st');
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if ((inConsumerBuilder || inHookBuilder) && lookingForParams) {
      params = node.parameters;
      lookingForParams = false;
    }
    super.visitFunctionExpression(node);
  }

  void migrateListener(InstanceCreationExpression node) {
    try {
      final provider = node.argumentList.arguments.firstWhere((element) =>
          element is NamedExpression &&
          element.name.label.name == 'provider') as NamedExpression;
      final onChange = node.argumentList.arguments.firstWhere((element) =>
          element is NamedExpression &&
          element.name.label.name == 'onChange') as NamedExpression;
      final fn = functionBody;
      final providerSource = context.sourceText
          .substring(provider.expression.offset, provider.expression.end);

      var onChangeSource = context.sourceText
          .substring(onChange.expression.offset, onChange.expression.end);
      if (onChange.expression is FunctionExpression) {
        final onChangeFunction = onChange.expression as FunctionExpression;
        onChangeSource =
            '(${context.sourceText.substring(onChangeFunction.parameters!.parameters[1].offset, onChangeFunction.end)}';
      } else if (onChange.expression is SimpleIdentifier &&
          onChange.staticType is FunctionType) {
        final functionName = onChange.expression as SimpleIdentifier;
        functionNeedsMigration.add(functionName.name);
        migrateOnChangeFunction(functionName.name);
      }

      final child = node.argumentList.arguments.firstWhere((element) =>
              element is NamedExpression && element.name.label.name == 'child')
          as NamedExpression;
      final childSource = context.sourceText
          .substring(child.expression.offset, child.expression.end);
      if (fn is BlockFunctionBody) {
        yieldPatch('ref.listen($providerSource, $onChangeSource);',
            fn.block.leftBracket.end, fn.block.leftBracket.end);
      } else if (fn is ExpressionFunctionBody) {
        yieldPatch('{\nref.listen($providerSource, $onChangeSource);return ',
            fn.offset, fn.expression.offset);
        yieldPatch(';}', fn.endToken.offset, fn.endToken.end);
      }

      yieldPatch(childSource, node.offset, node.end);
    } catch (e, st) {
      print(
          'Error in migration tool when attempting to migrate a ProviderListener\n$e\n$st');
    }
  }

  ProviderType inProvider = ProviderType.none;
  bool inAutoDisposeProvider = false;
  String providerTypeArgs = '';
  @override
  void visitTypeName(TypeName node) {
    final typeName = node.type?.getDisplayString(withNullability: true);

    try {
      if (typeName?.contains('ProviderReference') ?? false) {
        final autoDisposePrefix = inAutoDisposeProvider ? 'AutoDispose' : '';
        switch (inProvider) {
          case ProviderType.stream:
            yieldPatch(
                '${autoDisposePrefix}StreamProviderRef<$providerTypeArgs>',
                node.name.offset,
                node.name.end);
            break;
          case ProviderType.future:
            yieldPatch(
                '${autoDisposePrefix}FutureProviderRef<$providerTypeArgs>',
                node.name.offset,
                node.name.end);
            break;
          case ProviderType.plain:
            yieldPatch('${autoDisposePrefix}ProviderRef<$providerTypeArgs>',
                node.name.offset, node.name.end);
            break;
          case ProviderType.state:
            yieldPatch(
                '${autoDisposePrefix}StateProviderRef<$providerTypeArgs>',
                node.name.offset,
                node.name.end);
            break;
          case ProviderType.statenotifier:
            yieldPatch(
                '${autoDisposePrefix}StateNotifierProviderRef<$providerTypeArgs>',
                node.name.offset,
                node.name.end);
            break;
          case ProviderType.changenotifier:
            yieldPatch(
                '${autoDisposePrefix}ChangeNotifierProviderRef<$providerTypeArgs>',
                node.name.offset,
                node.name.end);
            break;
          case ProviderType.none:
            yieldPatch('ProviderRefBase', node.name.offset, node.name.end);
            break;
        }
      }
    } catch (e, st) {
      print('Error in migration tool when visiting type $typeName\n$e\n$st');
    }

    super.visitTypeName(node);
  }

  void updateProviderType(String type, DartType staticType) {
    try {
      final isInRiverpod = staticType.element?.declaration?.source?.uri.path
              .startsWith('riverpod') ??
          false;
      final isInFlutterRiverpod = staticType
              .element?.declaration?.source?.uri.path
              .startsWith('flutter_riverpod') ??
          false;

      withinScopedProvider = false;
      if (type.contains('ProviderContainer') ||
          type.contains('ProviderOverride') ||
          type.contains('ProviderScope') ||
          (!isInRiverpod && !isInFlutterRiverpod)) {
        providerTypeArgs = '';
        inProvider = ProviderType.none;
        return;
      }
      if (type.contains('FutureProvider')) {
        inProvider = ProviderType.future;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else if (type.contains('StreamProvider')) {
        inProvider = ProviderType.stream;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else if (type.contains('StateNotifierProvider')) {
        inProvider = ProviderType.statenotifier;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else if (type.contains('ChangeNotifierProvider')) {
        inProvider = ProviderType.changenotifier;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else if (type.contains('StateProvider')) {
        inProvider = ProviderType.state;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else if (type.contains('ScopedProvider')) {
        inProvider = ProviderType.plain;
        withinScopedProvider = true;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else if (type.contains('Provider')) {
        inProvider = ProviderType.plain;
        providerTypeArgs =
            type.substring(type.indexOf('<') + 1, type.lastIndexOf('>'));
      } else {
        providerTypeArgs = '';
        inProvider = ProviderType.none;
      }
      if (type.contains('AutoDispose')) {
        inAutoDisposeProvider = true;
      }
      if (type.contains('Family')) {
        // Too many type args for ProviderRef, so we get all but the last type argument which is the family parameter
        providerTypeArgs =
            providerTypeArgs.substring(0, providerTypeArgs.lastIndexOf(','));
      }
    } catch (e, st) {
      // Can't know anything if we ran into an exception
      providerTypeArgs = '';
      inAutoDisposeProvider = false;
      inProvider = ProviderType.none;

      print(
          'Error in migration tool while trying to get type arguments from $type\n$e\n$st');
    }
  }

  bool withinScopedProvider = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType?.getDisplayString(withNullability: true);

    try {
      if (type != null) {
        if (type.contains('Consumer')) {
          inConsumerBuilder = true;
          lookingForParams = true;
        }
        if (type.contains('HookBuilder')) {
          inHookBuilder = true;
          lookingForParams = true;
          hookBuilder = node.constructorName;
        }
        if (type.contains('ProviderListener')) {
          migrateListener(node);
          migrateParams();
          migrateClass();
        } else if (!type.contains('Family') &&
            type.contains('Provider') &&
            type.contains('Scoped')) {
          yieldPatch(type.replaceAll('Scoped', ''), node.constructorName.offset,
              node.constructorName.end);
          final functionExpression =
              node.argumentList.arguments.first as FunctionExpression;
          yieldPatch(
              'ref',
              functionExpression.parameters!.parameters.first.offset,
              functionExpression.parameters!.parameters.first.end);
        } else if (type.contains('Provider') &&
            !type.contains('ProviderOverride') &&
            !type.contains('ProviderScope') &&
            !type.contains('ProviderContainer') &&
            !type.contains('Family') &&
            node.constructorName.type.typeArguments == null) {
          updateProviderType(type, node.staticType!);
          if (inProvider != ProviderType.none) {
            yieldPatch('<$providerTypeArgs>', node.constructorName.type.end,
                node.constructorName.type.end);
          }
        }
        updateProviderType(type, node.staticType!);
      }
    } catch (e, st) {
      print(
          'Error in migration tool when visiting InstanceCreationExpression $type\n$e\n$st');
    }
    super.visitInstanceCreationExpression(node);
    inProvider = ProviderType.none;
    inConsumerBuilder = false;
    inHookBuilder = false;
    inAutoDisposeProvider = false;
  }

  @override
  void visitInvocationExpression(InvocationExpression node) {
    final type = node.staticType!.getDisplayString(withNullability: true);

    try {
      updateProviderType(type, node.staticType!);

      // Add type parameters if not already there
      if (type.contains('Provider') &&
          !type.contains('ProviderScope') &&
          !type.contains('Override') &&
          !type.contains('ProviderListener') &&
          inProvider != ProviderType.none) {
        final constructor =
            node.function.staticType?.getDisplayString(withNullability: true) ??
                '';

        if (!constructor.contains('Family')) {
          if (node.typeArguments == null) {
            yieldPatch('<$providerTypeArgs>', node.argumentList.offset,
                node.argumentList.offset);
          }
        }
      }
    } catch (e, st) {
      print(
          'Error in migration tool while visiting invocation expression and migrating provider type params $type\n$e\n$st');
    }
    super.visitInvocationExpression(node);
    inProvider = ProviderType.none;
    inAutoDisposeProvider = false;
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final functionName = node.function.toSource();
    if (withinClass == ClassType.none && !functionName.startsWith('use')) {
      if (functionName == 'watch' && withinScopedProvider) {
        yieldPatch('ref.watch', node.function.offset, node.function.end);
      }
      super.visitFunctionExpressionInvocation(node);
      return;
    }
    if (functionName == 'watch' || functionName == 'useProvider') {
      migrateParams();
      migrateClass();

      // watch(provider) => watch(provider.notifier)
      // useProvider(provider) => useProvider(provider.notifier)
      yieldPatch('ref.watch', node.function.offset, node.function.end);
    } else if (functionName.startsWith('use')) {
      if (RiverpodHooksProviderInfo.shouldMigrate(functionName)) {
        migrateConsumerHookFunctionCall(node.argumentList);
        migrateClass();
        migrateParams();
      }
    }

    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final functionName = node.name.name;
    if (RiverpodHooksProviderInfo.shouldMigrate(functionName)) {
      migrateFunctionDeclaration(node);
    }

    functionDecls[node.name.name] = node;
    migrateOnChangeFunction(node.name.name);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    try {
      final functionName = node.methodName.toSource();
      final target =
          node.realTarget?.staticType?.getDisplayString(withNullability: true);
      if (target?.contains('ProviderContainer') ?? false) {
        // No need to migrate container methods unless refreshing FutureProvider
        if (functionName == 'refresh') {
          final firstArgStaticType = node
              .argumentList.arguments.first.staticType!
              .getDisplayString(withNullability: true);
          if (firstArgStaticType.contains('FutureProvider')
              // || firstArgStaticType.contains('StreamProvider')
              ) {
            yieldPatch('.future', node.argumentList.arguments.first.end,
                node.argumentList.arguments.first.end);
          } else if (firstArgStaticType.contains('StateNotifier')) {
            yieldPatch('.notifier', node.argumentList.arguments.first.end,
                node.argumentList.arguments.first.end);
          }
        }
        if (functionName == 'listen') {
          yieldPatch(', (value) {}', node.argumentList.arguments.first.end,
              node.argumentList.arguments.first.end);
        }
        super.visitMethodInvocation(node);
        return;
      }

      if (withinClass == ClassType.none && !functionName.startsWith('use')) {
        super.visitMethodInvocation(node);
        return;
      }
      // ref.read / ref.watch / context.read / context.watch, useProvider
      if (functionName == 'watch' || functionName == 'useProvider') {
        migrateParams();
        migrateClass();
        yieldPatch('ref.watch', node.offset, node.methodName.end);
      } else if (functionName == 'read' &&
          node.methodName.staticType!
              .getDisplayString(withNullability: true)
              .contains('Function<T>(Provider')) {
        migrateParams();
        migrateClass();
        yieldPatch('ref.read', node.offset, node.methodName.end);
      } else if (functionName == 'refresh') {
        migrateParams();
        migrateClass();
        yieldPatch('ref.refresh', node.offset, node.methodName.end);
        final firstArgStaticType = node.argumentList.arguments.first.staticType!
            .getDisplayString(withNullability: true);
        if (firstArgStaticType.contains('FutureProvider')
            // || firstArgStaticType.contains('StreamProvider')
            ) {
          yieldPatch('.future', node.argumentList.arguments.first.end,
              node.argumentList.arguments.first.end);
        } else if (firstArgStaticType.contains('StateNotifier')) {
          yieldPatch('.notifier', node.argumentList.arguments.first.end,
              node.argumentList.arguments.first.end);
        }
      } else if (functionName.startsWith('use')) {
        if (RiverpodHooksProviderInfo.shouldMigrate(functionName)) {
          migrateConsumerHookFunctionCall(node.argumentList);
          migrateClass();
          migrateParams();
        }
      }
    } catch (e, st) {
      print(
          'Error in migration tool while visiting a method declaration $node\n$e\n$st');
    }
    super.visitMethodInvocation(node);
  }

  void migrateStateful(String statefulName) {
    final statefulDeclaration = statefulDeclarations[statefulName];
    if (statefulDeclaration != null) {
      yieldPatch(
          'ConsumerStatefulWidget',
          statefulDeclaration.extendsClause!.superclass.offset,
          statefulDeclaration.extendsClause!.superclass.end);
    } else {
      statefulNeedsMigration.add(statefulName);
    }
  }

  void migrateOnChangeFunction(String functionName) {
    final methodDecl = methodDecls[functionName];
    if (methodDecl != null && functionNeedsMigration.contains(functionName)) {
      yieldPatch('', methodDecl.parameters!.parameters.first.offset,
          methodDecl.parameters!.parameters[1].offset);
    } else {
      final funcDecl = functionDecls[functionName];
      if (funcDecl != null && functionNeedsMigration.contains(functionName)) {
        yieldPatch(
            '',
            funcDecl.functionExpression.parameters!.parameters.first.offset,
            funcDecl.functionExpression.parameters!.parameters[1].offset);
      }
    }
  }
}
