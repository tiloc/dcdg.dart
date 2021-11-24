import 'dart:core';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dcdg/src/builders/diagram_builder.dart';
import 'package:dcdg/src/constants.dart';
import 'package:dcdg/src/type_name.dart';
import 'package:dcdg/src/type_namespace.dart';

class PlantUmlBuilder implements DiagramBuilder {
  String? _currentClass;
  List<String> _currentNamespace = [];

  final List<String> _lines = [
    '@startuml',
    'set namespaceSeparator $namespaceSeparator',
    '',
  ];

  final Set<String> _relationships = {};

  final _memberComments = <String, String>{};

  @override
  void addAggregation(FieldElement element) {
    final fieldType = namespacedTypeName(element);
    _relationships.add('$_currentClass o-- $fieldType');
  }

  @override
  void addField(FieldElement element) {
    final visibilityPrefix = getVisibility(element);
    final staticPrefix = element.isStatic ? '{static} ' : '';
    final name = element.name;
    final type = typeName(element);
    _lines.add('  $staticPrefix$visibilityPrefix$type $name');

    final documentationComment = element.documentationComment;
    if (documentationComment != null) {
      _memberComments[name] = documentationComment;
    }
  }

  @override
  void addInterface(InterfaceType element) {
    final interfaceElement = element.element;
    final interfaceClass = namespacedTypeName(interfaceElement);
    _relationships.add('$interfaceClass <|-- $_currentClass');
  }

  @override
  void addMethod(MethodElement element) {
    final visibilityPrefix = getVisibility(element);
    final staticPrefix = element.isStatic ? '{static} ' : '';
    final name = element.name;
    final type = element.returnType.getDisplayString(withNullability: true);
    _lines.add('  $staticPrefix$visibilityPrefix$type $name()');

    final documentationComment = element.documentationComment;
    if (documentationComment != null) {
      _memberComments[name] = documentationComment;
    }
  }

  @override
  void addMixin(InterfaceType element) {
    final mixinElement = element.element;
    final mixinClass = namespacedTypeName(mixinElement);
    _relationships.add('$mixinClass <|-- $_currentClass');
  }

  @override
  void addSuper(InterfaceType element) {
    final superElement = element.element;
    final superClass = namespacedTypeName(superElement);
    _relationships.add('$superClass <|-- $_currentClass');
  }

  @override
  void beginClass(ClassElement element) {
    _packageDelta(element);
    _currentClass = namespacedTypeName(element);
    final decl = element.isAbstract ? 'abstract class' : 'class';
    _lines.add('$decl $_currentClass {');
  }

  @override
  void endClass(ClassElement element) {
    _lines.add('}');
    _lines.add('');

    final documentationComment = element.documentationComment;
    if (documentationComment != null) {
      _lines.add('note top');
      _lines.add(_cleanComment(documentationComment));
      _lines.add('end note');
      _lines.add('');
    }

    _memberComments.entries.forEach((comment) {
      _lines.add('note right of $_currentClass::${comment.key}');
      _lines.add(_cleanComment(comment.value));
      _lines.add('end note');
      _lines.add('');
    });

    _currentClass = null;
    _memberComments.clear();
  }

  String _cleanComment(String comment) {
    return comment
        .replaceAll('/// ', '')
        .replaceAll('///', '')
        .replaceAll('[', '')
        .replaceAll(']', '');
  }

  final _namespacePattern = RegExp(r"\:\:");
  void _packageDelta(Element element) {
    final newNamespace = typeNamespace(element).split(_namespacePattern);
    newNamespace.removeLast();

    int diffBeginIndex = 0;
    // Step 1: Skip identical elements
    for (int i = 0; i < _currentNamespace.length; i++) {
      if (i < newNamespace.length) {
        if (_currentNamespace[i] == newNamespace[i]) {
          // Elements are the same - difference begins after the identical elements
          diffBeginIndex = i + 1;
        } else {
          break;
        }
      } else {
        // New namespace is shorter than current one
        break;
      }
    }

    // Step 2: Close existing namespace levels that are different from previous ones
    if (diffBeginIndex < _currentNamespace.length) {
      for (int i = _currentNamespace.length - 1; i >= diffBeginIndex; i--) {
        _lines.add("'Closing namespace ${_currentNamespace[i]}");
        _lines.add('}');
      }
    }

    // Step 3: Open new namespace levels
    for (int i = diffBeginIndex; i < newNamespace.length; i++) {
      final packageName = StringBuffer();
      for (int i2 = 0; i2 <= i; i2++) {
        if (i2 > 0) {
          packageName.write('::');
        }
        packageName.write(newNamespace[i2]);
      }

      final colorHex =
          (255 - 5 * i).toRadixString(16).toUpperCase().padLeft(2, '0');
      _lines.add('namespace $packageName #$colorHex$colorHex$colorHex {');
    }

    _currentNamespace = newNamespace;
  }

  String namespacedTypeName(Element element) =>
      '"${typeNamespace(element)}${typeName(element, withNullability: false)}"';

  String getVisibility(Element element) {
    return element.isPrivate
        ? '-'
        : element.hasProtected
            ? '#'
            : '+';
  }

  @override
  void printContent(void Function(String content) printer) {
    final content = ([
      ..._lines,
      ...List<String>.filled(_currentNamespace.length, '}', growable: false),
      '',
      ..._relationships.toList(growable: false),
      '',
      '@enduml'
    ]).join('\n');
    printer(content);
  }

  @override
  void writeContent(File file) {
    printContent(file.writeAsStringSync);
  }
}
