import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_colors.dart';
import 'log_body_format.dart';

/// Tones a parsed [LogBody] for rendering inside a `Text.rich`.
///
/// [base] carries the row's own colour — the level tone in the developer log,
/// the priority tone in a stream — so JSON syntax colouring layers on top of
/// whatever the row already means rather than replacing it.
List<TextSpan> logBodySpans(
  LogBody body, {
  required TextStyle base,
  required AppPalette palette,
}) {
  return [
    for (final span in body.spans)
      TextSpan(
        text: span.text,
        style: switch (span.kind) {
          // Plain runs keep the row's tone; only JSON gets a hue.
          LogSpanKind.plain => base,
          LogSpanKind.punctuation => base.copyWith(color: palette.textMuted),
          LogSpanKind.key => base.copyWith(color: palette.jsonKey),
          LogSpanKind.string => base.copyWith(color: palette.jsonString),
          LogSpanKind.number => base.copyWith(color: palette.jsonNumber),
          LogSpanKind.literal => base.copyWith(color: palette.jsonLiteral),
        },
      ),
  ];
}
