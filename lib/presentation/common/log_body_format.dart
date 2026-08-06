/// Turns a one-line log message into the readable, colourable form the
/// developer log renders.
///
/// Records are stored one per line, so `--machine` output arrives as a single
/// run of JSON hundreds of characters wide. Re-indenting it and tagging each
/// token is what makes that blob skimmable.
library;

/// What a run of text in a log body is, so the view can tone it.
enum LogSpanKind {
  /// Anything outside a JSON payload — the `output: ` head, a plain message,
  /// or the `… (+22800 chars)` tail of a truncated blob.
  plain,

  /// Braces, brackets, commas, colons and the indentation between them.
  punctuation,

  /// A string used as an object key.
  key,

  /// A string value.
  string,
  number,

  /// `true`, `false` or `null`.
  literal,
}

/// One toned run of a log body.
class LogSpan {
  const LogSpan(this.text, this.kind);

  final String text;
  final LogSpanKind kind;

  @override
  String toString() => '${kind.name}(${text.replaceAll('\n', r'\n')})';
}

/// A log message ready to render: its spans, and whether any JSON was found.
class LogBody {
  const LogBody(this.spans, {required this.isJson});

  /// A message with no JSON payload — one plain span.
  factory LogBody.plain(String text) =>
      LogBody([LogSpan(text, LogSpanKind.plain)], isJson: false);

  final List<LogSpan> spans;

  /// True when a payload was re-indented, which is also what decides whether a
  /// row is worth collapsing.
  final bool isJson;

  /// The rendered text, for copying and for measuring height.
  String get text => spans.map((s) => s.text).join();

  int get lineCount => '\n'.allMatches(text).length + 1;

  /// The first [maxLines] lines, spans intact. Used for the collapsed row.
  LogBody take(int maxLines) {
    if (maxLines <= 0 || lineCount <= maxLines) return this;
    final kept = <LogSpan>[];
    var lines = 1;
    for (final span in spans) {
      final breaks = '\n'.allMatches(span.text).length;
      if (lines + breaks < maxLines + 1) {
        kept.add(span);
        lines += breaks;
        continue;
      }
      // The span that crosses the limit is cut at the newline that reaches it.
      final allowed = maxLines - lines;
      final cut = _indexOfNthNewline(span.text, allowed);
      if (cut > 0) kept.add(LogSpan(span.text.substring(0, cut), span.kind));
      break;
    }
    return LogBody(kept, isJson: isJson);
  }

  static int _indexOfNthNewline(String text, int n) {
    if (n <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] != '\n') continue;
      if (++seen == n) return i;
    }
    return text.length;
  }
}

/// Parses a stored log message into a [LogBody].
class LogBodyFormat {
  const LogBodyFormat._();

  static const _indent = '  ';

  /// The marker [CommandRunner] writes in place of a newline, so a command's
  /// multi-line output survives as one log line.
  static const _newlineMarker = '⏎';

  /// Splits [message] into its head and a re-indented JSON payload.
  ///
  /// Lenient by design: `--machine` output is truncated mid-object once it
  /// passes the runner's cap, so the scanner never requires a well-formed
  /// document — it tones what it can read and passes the rest through.
  static LogBody parse(String message) {
    final restored = message
        .replaceAll(' $_newlineMarker ', '\n')
        .replaceAll(_newlineMarker, '\n');
    final start = _payloadStart(restored);
    if (start < 0) return LogBody.plain(restored);

    final head = restored.substring(0, start);
    final spans = <LogSpan>[
      if (head.isNotEmpty) LogSpan(head, LogSpanKind.plain),
      ..._scan(restored.substring(start)),
    ];
    return LogBody(spans, isJson: true);
  }

  /// Index of the payload's opening brace, or -1 when the message carries none.
  ///
  /// A lone `{` proves nothing — `exec: ... --arg={x}` would qualify — so the
  /// remainder has to look like an object or array of pairs.
  static int _payloadStart(String message) {
    for (var i = 0; i < message.length; i++) {
      final c = message[i];
      if (c != '{' && c != '[') continue;
      final rest = message.substring(i);
      if (_looksLikeJson(rest)) return i;
    }
    return -1;
  }

  static final _pair = RegExp(r'"\s*:');

  static bool _looksLikeJson(String candidate) {
    if (_pair.hasMatch(candidate)) return true;
    // An empty or scalar-only array still reads better re-indented.
    return RegExp(r'^\[\s*[\]\-\d"tfn]').hasMatch(candidate);
  }

  /// Single pass: emits pretty-printed, kind-tagged spans.
  static List<LogSpan> _scan(String src) {
    final spans = <LogSpan>[];
    var depth = 0;

    void punct(String text) => spans.add(LogSpan(text, LogSpanKind.punctuation));
    void breakLine() => punct('\n${_indent * depth}');

    var i = 0;
    while (i < src.length) {
      final c = src[i];

      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
        continue;
      }

      if (c == '{' || c == '[') {
        final close = c == '{' ? '}' : ']';
        // `{}` and `[]` stay on one line — an empty body split across three is
        // noise, not structure.
        final next = _nextMeaningful(src, i + 1);
        if (next != -1 && src[next] == close) {
          punct('$c$close');
          i = next + 1;
          continue;
        }
        depth++;
        punct(c);
        breakLine();
        i++;
        continue;
      }

      if (c == '}' || c == ']') {
        if (depth > 0) depth--;
        breakLine();
        punct(c);
        i++;
        continue;
      }

      if (c == ',') {
        punct(c);
        breakLine();
        i++;
        continue;
      }

      if (c == ':') {
        punct(': ');
        i++;
        continue;
      }

      if (c == '"') {
        final end = _endOfString(src, i);
        final text = src.substring(i, end);
        final after = _nextMeaningful(src, end);
        final isKey = after != -1 && src[after] == ':';
        spans.add(
          LogSpan(text, isKey ? LogSpanKind.key : LogSpanKind.string),
        );
        i = end;
        continue;
      }

      final word = _word(src, i);
      if (word != null) {
        spans.add(LogSpan(word.$1, word.$2));
        i = word.$1.length + i;
        continue;
      }

      // Not JSON any more — the truncation tail, or a suffix the runner
      // appended. Everything from here is passed through verbatim.
      spans.add(LogSpan(src.substring(i), LogSpanKind.plain));
      break;
    }
    return spans;
  }

  /// Index just past the closing quote of the string starting at [start].
  ///
  /// Runs to the end for a string the truncation cut in half.
  static int _endOfString(String src, int start) {
    var i = start + 1;
    while (i < src.length) {
      final c = src[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '"') return i + 1;
      i++;
    }
    return src.length;
  }

  static int _nextMeaningful(String src, int from) {
    for (var i = from; i < src.length; i++) {
      final c = src[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
      return i;
    }
    return -1;
  }

  static final _number = RegExp(r'^-?\d+(\.\d+)?([eE][+-]?\d+)?');

  /// A number or a `true`/`false`/`null` at [start], with its kind.
  static (String, LogSpanKind)? _word(String src, int start) {
    final rest = src.substring(start);
    for (final literal in const ['true', 'false', 'null']) {
      if (rest.startsWith(literal)) return (literal, LogSpanKind.literal);
    }
    final match = _number.firstMatch(rest);
    if (match != null) return (match.group(0)!, LogSpanKind.number);
    return null;
  }
}
