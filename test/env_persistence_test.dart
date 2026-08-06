import 'package:android_sdk_manager/core/platform/env_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

const _script = '/home/dev/.config/flutter_sdk_manager/env.sh';

void main() {
  group('upsertManagedBlock', () {
    test('appends a block to an existing rc file, keeping what was there', () {
      const rc = 'export EDITOR=vim\nalias ll="ls -la"\n';
      final out = upsertManagedBlock(rc, _script);

      expect(out, startsWith(rc));
      expect(out, contains(kEnvBlockStart));
      expect(out, contains(kEnvBlockEnd));
      expect(out, contains(_script));
    });

    test('applying twice leaves exactly one block', () {
      const rc = 'export EDITOR=vim\n';
      final once = upsertManagedBlock(rc, _script);
      final twice = upsertManagedBlock(once, _script);

      expect(twice, once, reason: 'the second run must be a no-op');
      expect(kEnvBlockStart.allMatches(twice).length, 1);
    });

    test('a changed script path rewrites the block rather than adding one', () {
      final first = upsertManagedBlock('', _script);
      final moved = upsertManagedBlock(first, '/opt/app/env.sh');

      expect(kEnvBlockStart.allMatches(moved).length, 1);
      expect(moved, contains('/opt/app/env.sh'));
      expect(moved, isNot(contains(_script)));
    });

    test('handles a file with no trailing newline', () {
      final out = upsertManagedBlock('export EDITOR=vim', _script);
      expect(out, contains('export EDITOR=vim\n'));
      expect(out, contains(kEnvBlockStart));
    });

    test('an empty file gets only the block', () {
      final out = upsertManagedBlock('', _script);
      expect(out, '$kEnvBlockStart\n${sourcingLine(_script)}\n$kEnvBlockEnd\n');
    });

    test('a half-written block is left alone rather than guessed at', () {
      // Someone deleted the end marker by hand. Rewriting from the start
      // marker would eat the rest of their file.
      final mangled = '$kEnvBlockStart\nsomething the user kept\n';
      final out = upsertManagedBlock(mangled, _script);
      expect(out, contains('something the user kept'));
    });
  });

  group('removeManagedBlock', () {
    test('restores the file byte for byte', () {
      const rc = 'export EDITOR=vim\nalias ll="ls -la"\n';
      final added = upsertManagedBlock(rc, _script);
      expect(removeManagedBlock(added), rc);
    });

    test('round-trips an empty file', () {
      expect(removeManagedBlock(upsertManagedBlock('', _script)), '');
    });

    test('a file without a block is returned untouched', () {
      const rc = 'export EDITOR=vim\n';
      expect(removeManagedBlock(rc), rc);
    });

    test('never grows a gap when applied repeatedly', () {
      const rc = 'export EDITOR=vim\n';
      var text = rc;
      for (var i = 0; i < 3; i++) {
        text = upsertManagedBlock(text, _script);
        text = removeManagedBlock(text);
      }
      expect(text, rc);
    });
  });

  group('upsertExport', () {
    test('adds the variable to an empty script', () {
      expect(
        upsertExport('', 'CHROME_EXECUTABLE', '/usr/bin/chromium'),
        'export CHROME_EXECUTABLE="/usr/bin/chromium"\n',
      );
    });

    test('replaces the value in place instead of appending a second line', () {
      final first = upsertExport('', 'CHROME_EXECUTABLE', '/usr/bin/chromium');
      final second =
          upsertExport(first, 'CHROME_EXECUTABLE', '/usr/bin/brave-browser');

      expect(second, 'export CHROME_EXECUTABLE="/usr/bin/brave-browser"\n');
      expect('export CHROME_EXECUTABLE'.allMatches(second).length, 1);
    });

    test('leaves other variables alone', () {
      const existing = 'export ANDROID_HOME="/opt/sdk"\n';
      final out = upsertExport(existing, 'CHROME_EXECUTABLE', '/usr/bin/x');
      expect(out, contains('export ANDROID_HOME="/opt/sdk"'));
      expect(out, contains('export CHROME_EXECUTABLE="/usr/bin/x"'));
    });

    test('collapses duplicates a hand-edit may have left', () {
      const messy = 'export A="1"\nexport CHROME_EXECUTABLE="/old"\n'
          'export B="2"\nexport CHROME_EXECUTABLE="/older"\n';
      final out = upsertExport(messy, 'CHROME_EXECUTABLE', '/new');

      expect('CHROME_EXECUTABLE'.allMatches(out).length, 1);
      expect(out, contains('export A="1"'));
      expect(out, contains('export B="2"'));
    });
  });

  group('shellQuote', () {
    test('a path with spaces needs no escaping beyond the quotes', () {
      expect(
        exportLine('CHROME_EXECUTABLE', '/Applications/Google Chrome.app'),
        'export CHROME_EXECUTABLE="/Applications/Google Chrome.app"',
      );
    });

    test('escapes what would otherwise break the sourcing shell', () {
      // A literal $ or " in a path would end the string or expand a variable.
      expect(shellQuote(r'/opt/we"ird'), r'/opt/we\"ird');
      expect(shellQuote(r'/opt/$HOME'), r'/opt/\$HOME');
      expect(shellQuote(r'/opt/back\slash'), r'/opt/back\\slash');
    });
  });
}
