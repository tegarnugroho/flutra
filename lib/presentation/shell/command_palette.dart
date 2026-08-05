import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../common/compact_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One searchable destination shown by [showCommandPalette].
class PaletteEntry {
  const PaletteEntry({
    required this.index,
    required this.icon,
    required this.label,
    this.group,
  });

  /// Index of the destination in the shell's navigation index space.
  final int index;

  final IconData icon;
  final String label;

  /// The pane section the destination sits under ("Android", "Flutter").
  final String? group;
}

/// Opens the jump-to-page palette. Returns the chosen [PaletteEntry.index], or
/// null if the user dismissed it.
Future<int?> showCommandPalette(
  BuildContext context, {
  required List<PaletteEntry> entries,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _CommandPalette(entries: entries),
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.entries});

  final List<PaletteEntry> entries;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();

  late List<PaletteEntry> _matches = widget.entries;
  int _highlighted = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() {
      _matches = _rank(widget.entries, query);
      _highlighted = 0;
    });
  }

  void _move(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % _matches.length;
      if (_highlighted < 0) _highlighted += _matches.length;
    });
  }

  void _submit() {
    if (_matches.isEmpty) return;
    Navigator.pop(context, _matches[_highlighted].index);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CompactField(
              controller: _controller,
              placeholder: 'Go to page…',
              autofocus: true,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            if (_matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No matching page', style: AppTextStyles.caption),
              )
            else
              // Every destination fits without scrolling today; the list still
              // scrolls if more are added.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _matches.length,
                  itemBuilder: (context, i) => _PaletteRow(
                    entry: _matches[i],
                    highlighted: i == _highlighted,
                    palette: palette,
                    onHover: () => setState(() => _highlighted = i),
                    onTap: () => Navigator.pop(context, _matches[i].index),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            onPressed: _matches.isEmpty ? null : _submit,
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }
}

/// Filters and orders [entries] for [query].
///
/// Three tiers, best first: prefix match, substring match, then subsequence
/// (so "sdkm" still finds "SDK manager"). Within a tier the pane order wins,
/// which keeps an empty query showing the sidebar exactly as it is.
List<PaletteEntry> _rank(List<PaletteEntry> entries, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;

  final ranked = <(int, PaletteEntry)>[];
  for (final entry in entries) {
    final haystack = '${entry.label} ${entry.group ?? ''}'.toLowerCase();
    if (haystack.startsWith(q)) {
      ranked.add((0, entry));
    } else if (haystack.contains(q)) {
      ranked.add((1, entry));
    } else if (_isSubsequence(q, haystack)) {
      ranked.add((2, entry));
    }
  }
  ranked.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final r in ranked) r.$2];
}

/// Whether every character of [needle] appears in [haystack] in order.
bool _isSubsequence(String needle, String haystack) {
  var n = 0;
  for (var h = 0; h < haystack.length && n < needle.length; h++) {
    if (haystack[h] == needle[n]) n++;
  }
  return n == needle.length;
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.entry,
    required this.highlighted,
    required this.palette,
    required this.onHover,
    required this.onTap,
  });

  final PaletteEntry entry;
  final bool highlighted;
  final AppPalette palette;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: highlighted ? palette.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(AppShape.radiusControl),
          ),
          child: Row(
            children: [
              Icon(entry.icon, size: 14, color: palette.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  style: highlighted
                      ? AppTextStyles.navItemSelected
                      : AppTextStyles.navItem,
                ),
              ),
              if (entry.group != null)
                Text(entry.group!, style: AppTextStyles.caption),
            ],
          ),
        ),
      ),
    );
  }
}
