import 'package:codemod/codemod.dart';

/// The lateste version of riverpod that migrated code should be updated to
const latestVersion = '1.0.0-dev.4';

/// Migrates the pubspec to the [latestVersion]
Stream<Patch> versionMigrationSuggestor(FileContext context) async* {
  final matches = RegExp(
          r'riverpod:\s+\^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?')
      .allMatches(context.sourceText);
  for (final m in matches) {
    yield Patch('riverpod: ^$latestVersion', m.start, m.end);
  }
}
