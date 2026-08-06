import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/di/injection.dart';
import '../../../infrastructure/sdk/path_probe_service.dart';
import '../../common/compact_field.dart';
import '../../common/copy_icon_button.dart';
import '../../common/outlined_action_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'path_candidate_dialog.dart';

/// What a path row is probing for, which decides how it validates and whether
/// it can offer a folder picker.
enum PathKind { androidSdk, flutterSdk, url }

/// A settings row that shows one effective value, and edits it in place.
///
/// View state answers "what is in force and where did it come from" with a
/// single line. The input, picker and validation only exist while editing —
/// an always-visible empty field next to a detected value reads as two
/// competing answers.
class PathSettingRow extends StatefulWidget {
  const PathSettingRow({
    super.key,
    required this.label,
    required this.description,
    required this.kind,
    required this.overridePath,
    required this.detected,
    required this.onApply,
    required this.editing,
    required this.onBeginEdit,
    required this.onEndEdit,
    this.loading = false,
    this.onScan,
    this.scanning = false,
  });

  final String label;
  final String description;
  final PathKind kind;

  /// The user's override; null or empty means auto-detect.
  ///
  /// Not named `override` — that shadows the `@override` annotation for every
  /// member declared after it.
  final String? overridePath;

  /// Where the tool was actually found.
  final String? detected;

  /// Persists an override. An empty string clears it.
  final ValueChanged<String> onApply;

  /// Only one row edits at a time — the page owns that.
  final bool editing;
  final VoidCallback onBeginEdit;
  final VoidCallback onEndEdit;

  final bool loading;

  /// Searches the disk for installs of this kind. Null for rows that have
  /// nothing to scan for, such as the API URL.
  final Future<List<String>> Function()? onScan;

  /// True while any scan is walking the disk.
  final bool scanning;

  @override
  State<PathSettingRow> createState() => _PathSettingRowState();
}

class _PathSettingRowState extends State<PathSettingRow> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  PathProbe? _probe;
  bool _probing = false;

  /// True while the override is in force rather than auto-detection.
  bool get _isManual => (widget.overridePath ?? '').trim().isNotEmpty;

  /// What the app will actually use.
  String? get _effective =>
      _isManual ? widget.overridePath!.trim() : widget.detected;

  @override
  void didUpdateWidget(covariant PathSettingRow old) {
    super.didUpdateWidget(old);
    if (widget.editing && !old.editing) {
      _controller.text = _effective ?? '';
      _probe = null;
      _focus.requestFocus();
      _revalidate();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _revalidate);
  }

  Future<void> _revalidate() async {
    final value = _controller.text;
    final probes = getIt<PathProbeService>();
    if (widget.kind == PathKind.url) {
      setState(() => _probe = probes.probeBaseUrl(value));
      return;
    }
    setState(() => _probing = true);
    final probe = widget.kind == PathKind.androidSdk
        ? await probes.probeAndroidSdk(value)
        : await probes.probeFlutterSdk(value);
    if (!mounted) return;
    setState(() {
      _probe = probe;
      _probing = false;
    });
  }

  Future<void> _browse() async {
    final picked = await getDirectoryPath(
      confirmButtonText: 'Select',
      initialDirectory: _controller.text.trim().isEmpty
          ? null
          : _controller.text.trim(),
    );
    if (picked == null || !mounted) return;
    _controller.text = picked;
    await _revalidate();
  }

  /// Blocking only for URLs — a folder the app doesn't recognise may still be
  /// the right one, so its warning never stops a save.
  bool get _canSave =>
      widget.kind != PathKind.url || (_probe?.valid ?? true);

  void _save() {
    if (!_canSave) return;
    widget.onApply(_controller.text.trim());
    widget.onEndEdit();
  }

  void _resetToAuto() {
    widget.onApply('');
    widget.onEndEdit();
  }

  /// Searches the disk, then offers whatever turned up.
  ///
  /// A single hit that is already in force is still worth reporting — silence
  /// would read as a scan that failed.
  Future<void> _scan() async {
    final scan = widget.onScan;
    if (scan == null) return;
    final found = await scan();
    if (!mounted) return;

    final picked = await showPathCandidateDialog(
      context,
      label: widget.label,
      candidates: found,
      current: _effective,
    );
    if (picked == null || !mounted) return;
    widget.onApply(picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: widget.editing ? palette.accentBgTint : palette.windowBg,
        border: Border.all(
          color: widget.editing ? palette.accent : palette.border,
          width: AppShape.hairline,
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusGroup),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.label, style: text.rowTitle),
              if (widget.editing) ...[
                const SizedBox(width: 8),
                Text('— editing', style: text.caption),
              ],
              const Spacer(),
              if (!widget.editing) ...[
                if (widget.onScan != null) ...[
                  if (widget.scanning)
                    Text('Scanning…', style: text.caption)
                  else
                    _TextAction(
                      label: 'Scan',
                      muted: true,
                      onTap: _scan,
                    ),
                  const SizedBox(width: 12),
                ],
                _TextAction(label: 'Change', onTap: widget.onBeginEdit),
              ],
            ],
          ),
          if (!widget.editing) ...[
            const SizedBox(height: 4),
            Text(widget.description, style: text.caption),
            const SizedBox(height: 10),
            _ValueBar(
              value: _effective,
              isManual: _isManual,
              loading: widget.loading,
            ),
          ] else ...[
            const SizedBox(height: 10),
            _editor(palette, text),
          ],
        ],
      ),
    );
  }

  Widget _editor(AppPalette palette, AppTextStyles text) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onEndEdit,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CompactField(
                  controller: _controller,
                  focusNode: _focus,
                  icon: null,
                  placeholder: widget.kind == PathKind.url
                      ? 'https://api.example.com'
                      : r'C:\path\to\sdk',
                  onChanged: _onChanged,
                  onSubmitted: (_) => _save(),
                ),
              ),
              if (widget.kind != PathKind.url) ...[
                const SizedBox(width: 8),
                OutlinedActionButton(
                  icon: FluentIcons.folder_open,
                  label: 'Browse…',
                  dense: true,
                  onPressed: _browse,
                ),
              ],
              const SizedBox(width: 8),
              OutlinedActionButton(
                icon: FluentIcons.check_mark,
                label: 'Save',
                dense: true,
                onPressed: _canSave ? _save : null,
                tooltip: _canSave ? null : 'Fix the value first',
              ),
              const SizedBox(width: 4),
              _TextAction(label: 'Cancel', onTap: widget.onEndEdit),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _hint(palette, text)),
              _TextAction(
                label: 'Reset to auto-detect',
                muted: true,
                onTap: _resetToAuto,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hint(AppPalette palette, AppTextStyles text) {
    if (_probing) {
      return Text('Checking…', style: text.caption);
    }
    final probe = _probe;
    if (probe == null) return const SizedBox.shrink();
    // A failed folder probe is a warning; a failed URL is an error, because
    // nothing downstream could use it.
    final blocking = widget.kind == PathKind.url && !probe.valid;
    final color = probe.valid
        ? palette.statusOk
        : blocking
        ? palette.statusError
        : palette.statusWarn;
    return Row(
      children: [
        Icon(
          probe.valid ? FluentIcons.completed_solid : FluentIcons.warning,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            probe.message,
            style: text.caption.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The one effective value: where it came from, what it is, and a way to copy
/// it.
class _ValueBar extends StatelessWidget {
  const _ValueBar({
    required this.value,
    required this.isManual,
    required this.loading,
  });

  final String? value;
  final bool isManual;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final path = value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.sidebarBg,
        borderRadius: BorderRadius.circular(AppShape.radiusControl),
      ),
      child: Row(
        children: [
          _SourceBadge(isManual: isManual),
          const SizedBox(width: 10),
          Expanded(
            child: path == null || path.isEmpty
                ? Text(
                    loading ? '…' : 'Not found',
                    style: text.monoPath.copyWith(color: palette.textMuted),
                  )
                : Tooltip(
                    message: path,
                    child: Text(
                      path,
                      style: text.monoPath,
                      maxLines: 1,
                      // Middle-ellipsis: the tail of a path identifies it, the
                      // middle rarely does.
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
          ),
          if (path != null && path.isNotEmpty) ...[
            const SizedBox(width: 8),
            CopyIconButton(value: path, label: 'Path'),
          ],
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.isManual});

  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    final color = isManual ? palette.textMuted : palette.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: AppShape.hairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isManual ? 'Manual' : 'Auto',
        style: text.badge.copyWith(color: color),
      ),
    );
  }
}

/// A quiet inline action — accent by default, muted for secondary ones.
class _TextAction extends StatefulWidget {
  const _TextAction({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = AppTextStyles.fromPalette(palette);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: text.rowLabel.copyWith(
            color: widget.muted ? palette.textMuted : palette.accent,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: widget.muted
                ? palette.textMuted
                : palette.accent,
          ),
        ),
      ),
    );
  }
}
