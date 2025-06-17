//.title
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// Dart/Flutter (DF) Packages by dev-cetera.com & contributors. The use of this
// source code is governed by an MIT-style license described in the LICENSE
// file located in this project's root directory.
//
// See: https://opensource.org/license/mit
//
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//.title~

import 'dart:io';
import 'package:args/args.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:glob/glob.dart';

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

const VERSION = 'v0.1.0';
const TOOL_NAME = 'df_combinator';

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

void main(List<String> args) async {
  print('Running $TOOL_NAME...');
  try {
    // CREATE ARGUMENT PARSER
    final parser = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        help: 'Prints this help and usage information.',
        negatable: false,
      )
      ..addOption(
        'input',
        abbr: 'i',
        help: 'Specifies the directory to search in recursively.',
        defaultsTo: '.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Specifies the path for the combined output file.',
        defaultsTo: 'combined.dart.txt',
      )
      ..addOption(
        'extension',
        abbr: 'e',
        help: 'The file extension to search for (including the dot).',
        defaultsTo: '.dart',
      )
      ..addMultiOption(
        'blacklisted-files',
        help: 'File name patterns (globs) to exclude. Commas are AND.',
        splitCommas: true,
        defaultsTo: [],
      )
      ..addMultiOption(
        'blacklisted-folders',
        help: 'Folder name patterns (globs) to exclude. Commas are AND.',
        splitCommas: true,
        defaultsTo: [],
      )
      ..addFlag(
        'no-default-blacklist',
        help:
            'Disables the default folder blacklist (e.g., .dart_tool, build).',
        negatable: false,
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enables detailed, step-by-step logging.',
        negatable: false,
      );

    // PARSE ARGUMENTS
    final argsResult = parser.parse(args);
    if (argsResult['help'] as bool) {
      printHelp(parser);
      return;
    }

    final argInput = argsResult['input'] as String;
    final argOutput = argsResult['output'] as String;
    final argExtension = argsResult['extension'] as String;
    final argVerbose = argsResult['verbose'] as bool;
    final argBlacklistedFiles = argsResult['blacklisted-files'] as List<String>;
    final argBlacklistedFolders =
        argsResult['blacklisted-folders'] as List<String>;
    final argNoDefaultBlacklist = argsResult['no-default-blacklist'] as bool;

    // VALIDATE ARGUMENTS
    final sourceDir = Directory(argInput);
    if (!await sourceDir.exists()) {
      print('Error: Input directory does not exist: $argInput');
      exit(1);
    }

    // --- Core Logic ---

    // 1. GET A LIST OF ALL MATCHING FILES
    final files = Glob(
      '**/*$argExtension',
    ).listSync(root: argInput).whereType<File>().toList();

    if (argVerbose) {
      print(
        'Found ${files.length} files with extension "$argExtension" to consider.',
      );
    }

    // 2. FILTER THE FILES
    final finalBlacklistedFolders = [
      if (!argNoDefaultBlacklist) ...DEFAULT_FOLDER_BLACKLIST,
      ...argBlacklistedFolders,
    ];
    final finalBlacklistedFiles = [
      // CRITICAL: Always blacklist the output file itself to prevent recursion.
      p.basename(argOutput),
      ...argBlacklistedFiles,
    ];

    files.removeWhere((file) {
      final path = file.path;

      // Check against blacklisted folders
      for (final pattern in finalBlacklistedFolders) {
        if (Glob(pattern).matches(path)) {
          if (argVerbose) print('Skip: "$path" is in a blacklisted folder.');
          return true;
        }
      }

      // Check against blacklisted files
      for (final pattern in finalBlacklistedFiles) {
        if (Glob(pattern).matches(p.basename(path))) {
          if (argVerbose) print('Skip: "$path" is a blacklisted file.');
          return true;
        }
      }

      return false;
    });

    if (files.isEmpty) {
      print('No files left to combine after filtering. Exiting.');
      return;
    }

    if (argVerbose) {
      print('Combining the following ${files.length} files:');
      for (final file in files) {
        print('- ${file.path}');
      }
    }

    // 3. PROCESS FILES IN TWO PASSES

    // Pass 1: Collect all unique, non-local imports.
    final imports = <String>{};
    if (argVerbose) print('\n--- Pass 1: Collecting Imports ---');
    for (final file in files) {
      await _collectImports(file, imports, argVerbose);
    }

    // Pass 2: Write the final combined file.
    if (argVerbose) print('\n--- Pass 2: Writing Output File ---');
    final outputFile = File(argOutput);
    final sink = outputFile.openWrite();

    try {
      // Write a header for the combined file
      sink.writeln('// COMBINED FILE - GENERATED BY $TOOL_NAME $VERSION');
      sink.writeln(
        '// DO NOT EDIT THIS FILE DIRECTLY. It is an amalgamation of multiple source files.',
      );
      sink.writeln('// Generated on: ${DateTime.now().toUtc()} UTC\n');

      // Write all collected imports at the top
      if (imports.isNotEmpty) {
        sink.writeln('// --- Consolidated Imports ---');
        imports.toList()
          ..sort()
          ..forEach(sink.writeln);
        sink.writeln('// --- End of Imports ---\n');
      }

      // Write the content of each file
      for (final file in files) {
        await _processAndWriteFileContent(file, sink, argVerbose);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    print('\nSuccess!!! :D');
    print('Combined ${files.length} files into "${outputFile.path}".');
  } catch (e, stackTrace) {
    print('\nFailure!!! :(\nAn error occurred: ${e.toString()}');
    print(stackTrace);
    exit(1);
  }
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

void printHelp(ArgParser parser) {
  print(
    '$TOOL_NAME [$VERSION]\n\n'
    'Usage: dart run $TOOL_NAME [OPTIONS]\n\n'
    'A command-line tool to combine multiple source files into a single text file,\n'
    'useful for providing context to AI models. It intelligently handles imports\n'
    'by hoisting them to the top and commenting out originals.\n\n'
    'Options:\n'
    '${parser.usage}\n\n'
    'Example:\n'
    'dart run $TOOL_NAME -i lib -o context.txt -e .dart -v\n',
  );
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// PASS 1: Reads a file and adds its non-local imports to the `imports` set.
Future<void> _collectImports(
  File file,
  Set<String> imports,
  bool verbose,
) async {
  if (verbose) print('  - Reading imports from: ${file.path}');
  final lines = await file.readAsLines();
  for (var line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith("import 'package:") ||
        trimmedLine.startsWith("import 'dart:")) {
      imports.add(line);
    }
  }
}

/// PASS 2: Reads a file, comments out its imports/parts, and writes the rest
/// of its content to the output sink.
Future<void> _processAndWriteFileContent(
  File file,
  IOSink sink,
  bool verbose,
) async {
  if (verbose) print('  - Writing content from: ${file.path}');

  // Write a header comment with the original file path
  sink.writeln('// --------------------------------------------------');
  sink.writeln('// Source: ${file.path}');
  sink.writeln('// --------------------------------------------------');

  final lines = await file.readAsLines();
  for (var line in lines) {
    final trimmedLine = line.trim();
    // Comment out all import and part directives
    if (trimmedLine.startsWith('import ') ||
        trimmedLine.startsWith('part ') ||
        trimmedLine.startsWith('part of ')) {
      sink.writeln('// $line');
    } else {
      sink.writeln(line);
    }
  }
  // Add spacing after each file's content for readability
  sink.writeln();
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

/// Default folders to exclude from processing. These are patterns for `glob`.
const DEFAULT_FOLDER_BLACKLIST = [
  '**/.dart_tool/**',
  '**/.git/**',
  '**/.idea/**',
  '**/build/**',
];
