import 'package:flutra/domain/entities/release_note.dart';
import 'package:flutter_test/flutter_test.dart';

ReleaseNoteCategory _category(String subject) =>
    ReleaseNote.parse(subject).category;

void main() {
  group('category', () {
    test('a candidate-branch cherry-pick is an engine change', () {
      expect(
        _category('[flutter-3.24-candidate.0] Roll dart to 3.5.0 (#152233)'),
        ReleaseNoteCategory.engine,
      );
    });

    test('an engine.version sync is an engine change', () {
      expect(
        _category('Update engine.version to a1b2c3d4e5f6 (#151002)'),
        ReleaseNoteCategory.engine,
      );
    });

    test('platform cherry-picks keep their platform', () {
      expect(
        _category('[CP-stable][Android] Fix black screen on resume (#189605)'),
        ReleaseNoteCategory.android,
      );
      expect(
        _category('[CP-stable][iOS] Fix keyboard inset (#189606)'),
        ReleaseNoteCategory.ios,
      );
    });

    test('benchmarks, CI and test shards are infra', () {
      expect(
        _category('Add a benchmark for slivers (#100)'),
        ReleaseNoteCategory.infra,
      );
      expect(
        _category('Move the web shard to LUCI (#101)'),
        ReleaseNoteCategory.infra,
      );
      expect(
        _category('Skip a flaky test on Windows (#102)'),
        ReleaseNoteCategory.infra,
      );
    });

    test('changelog and docs are docs', () {
      expect(
        _category('Update CHANGELOG.md for 3.24.1 (#103)'),
        ReleaseNoteCategory.docs,
      );
      expect(
        _category('Fix docs for ListView.builder (#104)'),
        ReleaseNoteCategory.docs,
      );
    });

    test('anything unmatched falls through to other', () {
      expect(
        _category('Reland: make Slider tappable (#105)'),
        ReleaseNoteCategory.other,
      );
    });

    test('the engine wins over the platform it was cherry-picked for', () {
      expect(
        _category('[flutter-3.24-candidate.5][Android] Roll engine (#106)'),
        ReleaseNoteCategory.engine,
      );
    });
  });

  group('message', () {
    test('bracket prefixes and the PR number leave the message', () {
      final note = ReleaseNote.parse(
        '[CP-stable][Android] Fix black screen on resume (#189605)',
      );

      expect(note.message, 'Fix black screen on resume');
      expect(note.pullRequest, 189605);
      expect(note.raw, contains('[CP-stable]'));
    });

    test('a subject without a PR keeps a null number', () {
      final note = ReleaseNote.parse('Fix a thing');

      expect(note.pullRequest, isNull);
      expect(note.message, 'Fix a thing');
    });

    test('a number that is not a trailing PR is left in the message', () {
      final note = ReleaseNote.parse('Bump minSdk to 21 for the (#7) case');

      expect(note.pullRequest, isNull);
      expect(note.message, 'Bump minSdk to 21 for the (#7) case');
    });

    test('hashes are truncated to seven characters and marked', () {
      final note = ReleaseNote.parse(
        'Update engine.version to 4f2b1c9d8e7a6b5c4d3e2f10 (#900)',
      );

      expect(note.message, 'Update engine.version to 4f2b1c9');
      final hashes = note.spans.where((s) => s.isHash).map((s) => s.text);
      expect(hashes, ['4f2b1c9']);
    });

    test('short hex words are text, not hashes', () {
      final note = ReleaseNote.parse('Fix a faded decade of bad edges (#901)');

      expect(note.spans.where((s) => s.isHash), isEmpty);
      expect(note.message, 'Fix a faded decade of bad edges');
    });
  });
}
