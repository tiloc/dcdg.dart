import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dcdg/src/class_element_collector.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as path;

/// Fetch and return the desired class elements from the package
/// rooted at the given path.
Future<Iterable<ClassElement>> findClassElements({
  required String packagePath,
  required bool exportedOnly,
  required String searchPath,
}) async {
  String makePackageSubPath(String part0, [String part1 = '']) =>
      path.normalize(
        path.absolute(
          path.join(
            packagePath,
            part0,
            part1,
          ),
        ),
      );

  List<String> makePackageSubPaths(String part0) {
    final dartFiles = Glob(part0, recursive: true);

    final uniquePaths = Set<String>();

    try {
      dartFiles.listSync().forEach((e) => uniquePaths
          .add(path.normalize(path.absolute(packagePath, e.dirname))));

      return uniquePaths.toList(growable: false);
    } catch (_) {
      // Requested path doesn't exist
      return [];
    }
  }

  final includedPaths = [
    ...makePackageSubPaths('lib/**.dart'),
    ...makePackageSubPaths('bin/**.dart'),
    ...makePackageSubPaths('web/**.dart'),
  ];

  final contextCollection = AnalysisContextCollection(
    includedPaths: includedPaths,
  );

  final dartFiles = Directory(makePackageSubPath(searchPath))
      .listSync(recursive: true)
      .where((file) => path.extension(file.path) == '.dart')
      .where((file) => !exportedOnly || !file.path.contains('/src/'));

  final collector = ClassElementCollector(
    exportedOnly: exportedOnly,
  );
  for (final file in dartFiles) {
    try {
      final filePath = path.normalize(path.absolute(file.path));
      final context = contextCollection.contextFor(filePath);

      final unitResult = await context.currentSession.getResolvedUnit(filePath);
      if (unitResult is ResolvedUnitResult) {
        unitResult.libraryElement.accept(collector);
      }
    } catch (e) {
      // File analysis can fail, especially in irrelevant l10n files.
      stderr.writeln(
          'WARNING: Could not analyze file: $file. Contexts: $includedPaths.');
    }
  }

  return collector.classElements;
}
