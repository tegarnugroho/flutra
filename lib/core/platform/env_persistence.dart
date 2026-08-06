/// What persisting an environment variable achieved, and what the user still
/// has to do about it.
class EnvPersistResult {
  const EnvPersistResult({
    required this.success,
    this.restartRequired = false,
    this.note,
  });

  const EnvPersistResult.failed(String this.note)
      : success = false,
        restartRequired = false;

  final bool success;

  /// The value only reaches processes started later.
  final bool restartRequired;

  /// One line for the UI.
  final String? note;
}

/// The marker lines around the block this app owns in a shell rc file.
///
/// Everything between them is ours to rewrite; everything outside is the
/// user's and is never touched. Matching the exact strings is what makes
/// re-running idempotent rather than additive.
const String kEnvBlockStart = '# >>> flutra >>>';
const String kEnvBlockEnd = '# <<< flutra <<<';

/// The file the app writes its exports to, relative to the config directory.
const String kEnvScriptName = 'env.sh';

/// Shell-quotes [value] for a double-quoted export.
///
/// A path with a space is the common case; a path with a `"` or a `$` is rare
/// but would otherwise produce a file that breaks every shell that sources it.
String shellQuote(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(r'$', r'\$')
    .replaceAll('`', r'\`')
    .replaceAll('"', r'\"');

/// One `export NAME="value"` line.
String exportLine(String name, String value) =>
    'export $name="${shellQuote(value)}"';

/// Whether [pathValue] — the raw contents of a PATH variable — already lists
/// [directory].
///
/// Entry-wise rather than a substring test: `C:\dev\flutter\bin` must not read
/// as a hit for `C:\dev\flutter\bin2`, while a quoted entry or a trailing
/// separator names the same directory. Windows splits on `;` and compares
/// case-insensitively; every other platform splits on `:` and does not.
bool pathListContains(
  String pathValue,
  String directory, {
  required bool windows,
}) {
  String normalise(String raw) {
    var value = raw.trim();
    if (value.length > 1 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (windows) value = value.replaceAll('/', r'\');
    while (value.length > 1 &&
        (value.endsWith(r'\') || value.endsWith('/'))) {
      value = value.substring(0, value.length - 1);
    }
    return windows ? value.toLowerCase() : value;
  }

  final wanted = normalise(directory);
  if (wanted.isEmpty) return false;
  return pathValue
      .split(windows ? ';' : ':')
      .any((entry) => normalise(entry) == wanted);
}

/// The directories this app's `env.sh` appends to PATH, in file order.
///
/// Only the lines the app writes itself are read — a hand-edited export with a
/// different shape is left to the shell, not guessed at.
List<String> parseExportedPathEntries(String script) {
  final pattern = RegExp(r'^\s*export\s+PATH="\$PATH:(.*)"\s*$');
  final entries = <String>[];
  for (final line in script.split('\n')) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    final value = shellUnquote(match.group(1)!);
    if (value.isNotEmpty) entries.add(value);
  }
  return entries;
}

/// The inverse of [shellQuote].
String shellUnquote(String value) => value
    .replaceAll(r'\"', '"')
    .replaceAll(r'\`', '`')
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\\', r'\');

/// The contents of `env.sh` with [name] set to [value].
///
/// Rewrites the variable in place when it is already there, so the file holds
/// one line per variable however many times a fix runs.
String upsertExport(String existing, String name, String value) {
  final wanted = exportLine(name, value);
  final lines = existing.isEmpty ? <String>[] : existing.split('\n');
  final pattern = RegExp('^\\s*export\\s+$name=');

  var replaced = false;
  final out = <String>[];
  for (final line in lines) {
    if (pattern.hasMatch(line)) {
      // Keep the first occurrence's position; drop any duplicates below it.
      if (!replaced) {
        out.add(wanted);
        replaced = true;
      }
      continue;
    }
    out.add(line);
  }
  if (!replaced) out.add(wanted);

  // Exactly one trailing newline, whatever the input had.
  final body = out.where((l) => l.trim().isNotEmpty).join('\n');
  return body.isEmpty ? '' : '$body\n';
}

/// The line an rc file needs so a shell picks up [scriptPath].
String sourcingLine(String scriptPath) =>
    '[ -f "$scriptPath" ] && . "$scriptPath"';

/// Adds — or refreshes — this app's block in an rc file's [contents].
///
/// Idempotent by construction: an existing block is replaced wholesale, so
/// applying twice leaves one block, and applying after the script path changed
/// leaves one *correct* block. Anything outside the markers is returned byte
/// for byte.
String upsertManagedBlock(String contents, String scriptPath) {
  final block = '$kEnvBlockStart\n${sourcingLine(scriptPath)}\n$kEnvBlockEnd';
  final existing = _blockRange(contents);

  if (existing == null) {
    if (contents.isEmpty) return '$block\n';
    // Keep the file's own ending, then append the block after a blank line.
    final base = contents.endsWith('\n') ? contents : '$contents\n';
    return '$base\n$block\n';
  }

  return contents.replaceRange(existing.$1, existing.$2, block);
}

/// Removes this app's block, restoring what the file looked like before.
///
/// The inverse of [upsertManagedBlock]: applying one then the other returns
/// the original text, which is the property the uninstall path needs.
String removeManagedBlock(String contents) {
  final existing = _blockRange(contents);
  if (existing == null) return contents;

  var (start, end) = existing;
  // Swallow the newline the block sits on, and the blank line that was added
  // in front of it, so removing does not leave a growing gap behind.
  if (end < contents.length && contents[end] == '\n') end++;
  if (start >= 2 &&
      contents[start - 1] == '\n' &&
      contents[start - 2] == '\n') {
    start--;
  }
  return contents.replaceRange(start, end, '');
}

/// The character range of the managed block, or null when there is none.
(int, int)? _blockRange(String contents) {
  final start = contents.indexOf(kEnvBlockStart);
  if (start < 0) return null;
  final endMarker = contents.indexOf(kEnvBlockEnd, start);
  // A start without its end means someone edited the block by hand; leave the
  // file alone rather than guessing where it was meant to stop.
  if (endMarker < 0) return null;
  return (start, endMarker + kEnvBlockEnd.length);
}
