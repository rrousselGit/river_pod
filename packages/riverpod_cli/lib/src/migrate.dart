import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:codemod/codemod.dart';
import 'package:glob/glob.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:riverpod_cli/src/migrate/unified_syntax.dart';

import 'migrate/imports.dart';
import 'migrate/notifiers.dart';
import 'migrate/version.dart';

class MigrateCommand extends Command<void> {
  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Analyse a project using Riverpod and migrate it to the latest version available';

  @override
  Future<void> run() async {
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      stderr.writeln(
        'Pubspec not found! Are you in the root directory of your package / app?',
      );
      return;
    }
    final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
    final dep = pubspec.dependencies['hooks_riverpod'] ??
        pubspec.dependencies['flutter_riverpod'] ??
        pubspec.dependencies['riverpod'];

    VersionConstraint version;
    if (dep is HostedDependency) {
      version = dep.version;
    } else {
      throw UnimplementedError(
          'Migrating git and path dependencies can cause issues because of trying to understand riverpod versioning, please depend on an official package');
    }

    await runInteractiveCodemodSequence(
      filePathsFromGlob(Glob('**.dart', recursive: true)),
      [
        aggregate(
          [
            RiverpodImportAllMigrationSuggestor(),
            RiverpodNotifierChangesMigrationSuggestor(version),
          ],
        ),
        RiverpodHooksProviderInfo(version),
        RiverpodUnifiedSyntaxChangesMigrationSuggestor(version),
      ],
      args: argResults?.arguments ?? [],
    );

    await runInteractiveCodemod(
      filePathsFromGlob(Glob('pubspec.yaml', recursive: true)),
      versionMigrationSuggestor,
      args: argResults?.arguments ?? [],
    );
  }
}
