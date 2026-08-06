import 'package:equatable/equatable.dart';

/// What a release-note entry is about, derived from the commit subject.
///
/// Flutter's own commit conventions are the only signal available — the git
/// history carries no labels — so this is a best-effort read of the prefixes
/// the repository actually uses.
enum ReleaseNoteCategory {
  /// Engine rolls and `engine.version` syncs, plus release-candidate branches.
  engine,
  android,
  ios,

  /// Benchmarks, CI, test shards — changes to how Flutter is built and tested.
  infra,

  /// Changelog and documentation.
  docs,
  other;

  /// The pill label.
  String get label => name;
}

/// One run of an entry's message. [isHash] runs are commit hashes, rendered
/// in monospace and already truncated.
class ReleaseNoteSpan extends Equatable {
  const ReleaseNoteSpan(this.text, {this.isHash = false});

  final String text;
  final bool isHash;

  @override
  List<Object?> get props => [text, isHash];
}

/// A commit subject from the SDK's git history, parsed for display.
class ReleaseNote extends Equatable {
  const ReleaseNote({
    required this.raw,
    required this.category,
    required this.spans,
    this.pullRequest,
  });

  /// The subject exactly as git reported it.
  final String raw;

  final ReleaseNoteCategory category;

  /// The message with its `[…]` prefixes and trailing `(#123)` removed, split
  /// so hashes can be toned differently.
  final List<ReleaseNoteSpan> spans;

  /// The PR the commit landed through, when the subject names one.
  final int? pullRequest;

  /// The displayed message as plain text.
  String get message => spans.map((s) => s.text).join();

  /// Hashes shorter than this are words that happen to be hex ("added",
  /// "face"), not commits. Real short hashes in Flutter subjects are 10+.
  static const _minHashLength = 10;

  /// What git itself abbreviates to.
  static const _shortHashLength = 7;

  static final _prefix = RegExp(r'^\s*\[([^\]]*)\]\s*');
  static final _pullRequest = RegExp(r'\s*\(#(\d+)\)\s*$');
  static final _hash = RegExp('[0-9a-f]{$_minHashLength,40}');

  factory ReleaseNote.parse(String subject) {
    var rest = subject.trim();

    // Trailing "(#189605)" is the PR, not part of what the commit did.
    final pr = _pullRequest.firstMatch(rest);
    if (pr != null) {
      rest = rest.substring(0, pr.start);
    }

    // Leading "[CP-stable][Android]" tags classify the commit; they are noise
    // once the category pill says the same thing.
    final tags = <String>[];
    while (true) {
      final match = _prefix.firstMatch(rest);
      if (match == null) break;
      tags.add(match.group(1)!.trim());
      rest = rest.substring(match.end);
    }

    return ReleaseNote(
      raw: subject,
      category: categorise(tags, rest),
      spans: _split(rest.trim()),
      pullRequest: pr == null ? null : int.tryParse(pr.group(1)!),
    );
  }

  /// The category for a commit with [tags] and body [text].
  ///
  /// Order is deliberate: a cherry-pick onto a candidate branch is an engine
  /// concern first, and only then a platform one.
  static ReleaseNoteCategory categorise(List<String> tags, String text) {
    final lowerTags = tags.map((t) => t.toLowerCase()).toList();
    final lowerText = text.toLowerCase();

    bool tagMatches(bool Function(String) test) => lowerTags.any(test);

    if (tagMatches((t) => t.contains('candidate')) ||
        tagMatches((t) => t == 'engine') ||
        lowerText.contains('engine.version') ||
        lowerText.contains('roll engine')) {
      return ReleaseNoteCategory.engine;
    }
    if (tagMatches((t) => t == 'android' || t.startsWith('android'))) {
      return ReleaseNoteCategory.android;
    }
    if (tagMatches((t) => t == 'ios' || t.startsWith('ios'))) {
      return ReleaseNoteCategory.ios;
    }
    if (_infra.hasMatch(lowerText) || tagMatches(_infra.hasMatch)) {
      return ReleaseNoteCategory.infra;
    }
    if (_docs.hasMatch(lowerText) || tagMatches(_docs.hasMatch)) {
      return ReleaseNoteCategory.docs;
    }
    return ReleaseNoteCategory.other;
  }

  static final _infra = RegExp(
    r'benchmark|\bci\b|\btests?\b|\bshard|flake|\bcirrus\b|\bluci\b',
  );
  static final _docs = RegExp(r'changelog|\bdocs?\b|documentation|readme');

  /// Splits [text] so hashes come out as their own, truncated spans.
  static List<ReleaseNoteSpan> _split(String text) {
    if (text.isEmpty) return const [];
    final spans = <ReleaseNoteSpan>[];
    var index = 0;
    for (final match in _hash.allMatches(text)) {
      if (match.start > index) {
        spans.add(ReleaseNoteSpan(text.substring(index, match.start)));
      }
      spans.add(
        ReleaseNoteSpan(
          match.group(0)!.substring(0, _shortHashLength),
          isHash: true,
        ),
      );
      index = match.end;
    }
    if (index < text.length) {
      spans.add(ReleaseNoteSpan(text.substring(index)));
    }
    return spans;
  }

  @override
  List<Object?> get props => [raw, category, spans, pullRequest];
}
