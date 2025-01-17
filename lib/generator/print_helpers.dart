import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:recase/recase.dart';
import '../generator/data.dart';
import '../generator/helpers.dart';

/// Generates a [Spec] of a single enum definition.
Spec enumDefinitionToSpec(EnumDefinition definition) =>
    CodeExpression(Code('''enum ${definition.name} {
  ${removeDuplicatedBy(definition.values, (i) => i).map((v) => '$v, ').join()}
}'''));

String _fromJsonBody(ClassDefinition definition) {
  final buffer = StringBuffer();
  buffer.writeln('''switch (json['${definition.resolveTypeField}']) {''');

  for (final p in definition.factoryPossibilities) {
    buffer.writeln('''      case '$p':
        return ${p}.fromJson(json);''');
  }

  buffer.writeln('''      default:
    }
    return _\$${definition.name}FromJson(json);''');
  return buffer.toString();
}

String _toJsonBody(ClassDefinition definition) {
  final buffer = StringBuffer();
  buffer.writeln('''switch (resolveType) {''');

  for (final p in definition.factoryPossibilities) {
    buffer.writeln('''      case '$p':
        return (this as ${p}).toJson();''');
  }

  buffer.writeln('''      default:
    }
    return _\$${definition.name}ToJson(this);''');
  return buffer.toString();
}

/// Generates a [Spec] of a single class definition.
Spec classDefinitionToSpec(ClassDefinition definition) {
  final fromJson = definition.factoryPossibilities.isNotEmpty
      ? Constructor(
          (b) => b
            ..factory = true
            ..name = 'fromJson'
            ..requiredParameters.add(Parameter(
              (p) => p
                ..type = refer('Map<String, dynamic>')
                ..name = 'json',
            ))
            ..body = Code(_fromJsonBody(definition)),
        )
      : Constructor(
          (b) => b
            ..factory = true
            ..name = 'fromJson'
            ..lambda = true
            ..requiredParameters.add(Parameter(
              (p) => p
                ..type = refer('Map<String, dynamic>')
                ..name = 'json',
            ))
            ..body = Code('_\$${definition.name}FromJson(json)'),
        );

  final toJson = definition.factoryPossibilities.isNotEmpty
      ? Method(
          (m) => m
            ..name = 'toJson'
            ..returns = refer('Map<String, dynamic>')
            ..body = Code(_toJsonBody(definition)),
        )
      : Method(
          (m) => m
            ..name = 'toJson'
            ..lambda = true
            ..returns = refer('Map<String, dynamic>')
            ..body = Code('_\$${definition.name}ToJson(this)'),
        );

  return Class(
    (b) => b
      ..annotations
          .add(CodeExpression(Code('JsonSerializable(explicitToJson: true)')))
      ..name = definition.name
      ..extend =
          definition.extension != null ? refer(definition.extension) : null
      ..implements.addAll(definition.implementations.map((i) => refer(i)))
      ..constructors.add(Constructor())
      ..constructors.add(fromJson)
      ..methods.add(toJson)
      ..fields.addAll(definition.properties.map((p) {
        final annotations = <CodeExpression>[];
        if (p.override) annotations.add(CodeExpression(Code('override')));
        if (p.annotation != null) {
          annotations.add(CodeExpression(Code(p.annotation)));
        }
        final field = Field(
          (f) => f
            ..name = p.name
            ..type = refer(p.type)
            ..annotations.addAll(annotations),
        );
        return field;
      })),
  );
}

/// Generates a [Spec] of a mutation argument class.
Spec generateArgumentClassSpec(QueryDefinition definition) {
  return Class(
    (b) => b
      ..annotations
          .add(CodeExpression(Code('JsonSerializable(explicitToJson: true)')))
      ..name = '${definition.queryName}Arguments'
      ..extend = refer('JsonSerializable')
      ..constructors.add(Constructor(
        (b) => b
          ..optionalParameters.addAll(definition.inputs.map(
            (input) => Parameter(
              (p) => p
                ..name = input.name
                ..named = true
                ..toThis = true,
            ),
          )),
      ))
      ..constructors.add(Constructor(
        (b) => b
          ..factory = true
          ..name = 'fromJson'
          ..lambda = true
          ..requiredParameters.add(Parameter(
            (p) => p
              ..type = refer('Map<String, dynamic>')
              ..name = 'json',
          ))
          ..body = Code('_\$${definition.queryName}ArgumentsFromJson(json)'),
      ))
      ..methods.add(Method(
        (m) => m
          ..name = 'toJson'
          ..lambda = true
          ..returns = refer('Map<String, dynamic>')
          ..body = Code('_\$${definition.queryName}ArgumentsToJson(this)'),
      ))
      ..fields.addAll(definition.inputs.map(
        (p) => Field(
          (f) => f
            ..name = p.name
            ..type = refer(p.type)
            ..modifier = FieldModifier.final$,
        ),
      )),
  );
}

/// Generates a [Spec] of a query/mutation class.
Spec generateQueryClassSpec(QueryDefinition definition) {
  final sanitizedQueryStr = definition.query
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\$'), '\\\$')
      .trim();

  final String typeDeclaration = definition.inputs.isEmpty
      ? '${definition.queryName}, JsonSerializable'
      : '${definition.queryName}, ${definition.queryName}Arguments';

  final constructor = definition.inputs.isEmpty
      ? Constructor()
      : Constructor((b) => b
        ..optionalParameters.add(Parameter(
          (p) => p
            ..name = 'variables'
            ..toThis = true
            ..named = true,
        )));

  final fields = [
    Field(
      (f) => f
        ..annotations.add(CodeExpression(Code('override')))
        ..modifier = FieldModifier.final$
        ..type = refer('String')
        ..name = 'query'
        ..assignment = Code('\'$sanitizedQueryStr\''),
    ),
    Field(
      (f) => f
        ..annotations.add(CodeExpression(Code('override')))
        ..modifier = FieldModifier.final$
        ..type = refer('String')
        ..name = 'operationName'
        ..assignment = Code('\'${ReCase(definition.queryName).snakeCase}\''),
    ),
  ];

  if (definition.inputs.isNotEmpty) {
    fields.add(Field(
      (f) => f
        ..annotations.add(CodeExpression(Code('override')))
        ..modifier = FieldModifier.final$
        ..type = refer('${definition.queryName}Arguments')
        ..name = 'variables',
    ));
  }

  return Class(
    (b) => b
      ..name = '${definition.queryName}Query'
      ..extend = refer('GraphQLQuery<$typeDeclaration>')
      ..constructors.add(constructor)
      ..fields.addAll(fields)
      ..methods.add(Method(
        (m) => m
          ..annotations.add(CodeExpression(Code('override')))
          ..returns = refer(definition.queryName)
          ..name = 'parse'
          ..requiredParameters.add(Parameter(
            (p) => p
              ..type = refer('Map<String, dynamic>')
              ..name = 'json',
          ))
          ..lambda = true
          ..body = Code('${definition.queryName}.fromJson(json)'),
      )),
  );
}

/// Gathers and generates a [Spec] of a whole query/mutation and its
/// dependencies into a single library file.
Spec generateLibrarySpec(QueryDefinition definition) {
  final importDirectives = [
    Directive.import('package:json_annotation/json_annotation.dart'),
  ];

  if (definition.generateHelpers) {
    importDirectives.insert(
      0,
      Directive.import('package:artemis/artemis.dart'),
    );
  }

  if (definition.customParserImport != null) {
    importDirectives.add(Directive.import(definition.customParserImport));
  }

  importDirectives.addAll(definition.customImports
      .map((customImport) => Directive.import(customImport)));

  final bodyDirectives = <Spec>[
    CodeExpression(Code('part \'${definition.basename}.query.g.dart\';')),
  ];

  bodyDirectives.addAll(definition.classes
      .whereType<ClassDefinition>()
      .map(classDefinitionToSpec));
  bodyDirectives.addAll(
      definition.classes.whereType<EnumDefinition>().map(enumDefinitionToSpec));

  if (definition.inputs.isNotEmpty) {
    bodyDirectives.add(generateArgumentClassSpec(definition));
  }
  if (definition.generateHelpers) {
    bodyDirectives.add(generateQueryClassSpec(definition));
  }

  return Library(
    (b) => b..directives.addAll(importDirectives)..body.addAll(bodyDirectives),
  );
}

/// Emit a [Spec] into a String, considering Dart formatting.
String specToString(Spec spec) {
  final emitter = DartEmitter();
  return DartFormatter().format(spec.accept(emitter).toString());
}

/// Generate Dart code typings from a query or mutation and its response from
/// a [QueryDefinition] into a buffer.
void writeDefinitionsToBuffer(StringBuffer buffer, QueryDefinition definition) {
  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND\n');
  buffer.write(specToString(generateLibrarySpec(definition)));
}
