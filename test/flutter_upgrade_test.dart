import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutra/application/flutter_sdk/flutter_upgrade_cubit.dart';
import 'package:flutra/core/command/command_result.dart';
import 'package:flutra/presentation/common/app_loader.dart';
import 'package:flutra/presentation/flutter_sdk/widgets/upgrade_progress_view.dart';
import 'package:flutra/presentation/flutter_sdk/widgets/upgrade_stepper.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => FluentApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.dark,
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SizedBox(width: 420, child: child),
  ),
);

CommandOutputLine _line(String text) => CommandOutputLine(text);

/// Folds [texts] into a fresh state, one line at a time, as the cubit does.
UpgradeProgress _fold(
  List<String> texts, {
  Duration phaseElapsed = Duration.zero,
  UpgradeProgress? from,
}) {
  var state = from ?? const UpgradeProgress(running: true, started: true);
  for (final text in texts) {
    state = applyUpgradeLine(state, _line(text), phaseElapsed);
  }
  return state;
}

void main() {
  group('upgradePhaseFor', () {
    test('maps the lines flutter upgrade prints onto their phase', () {
      expect(upgradePhaseFor(r'Upgrading Flutter to 3.44.10 from 3.44.9 in C:\f'),
          UpgradePhase.downloading);
      expect(upgradePhaseFor('Receiving objects:  42% (1234/2929)'),
          UpgradePhase.downloading);
      expect(
          upgradePhaseFor(
              'Downloading Windows x64 Dart SDK from Flutter engine abc123...'),
          UpgradePhase.downloading);
      expect(upgradePhaseFor('Unzipping Dart SDK...'), UpgradePhase.extracting);
      expect(upgradePhaseFor('Expanding downloaded archive...'),
          UpgradePhase.extracting);
      expect(upgradePhaseFor('Building flutter tool...'),
          UpgradePhase.buildingTool);
      expect(upgradePhaseFor('Running pub upgrade...'),
          UpgradePhase.buildingTool);
      expect(upgradePhaseFor('Downloading Material fonts...          1,204ms'),
          UpgradePhase.upgradingEngine);
      expect(upgradePhaseFor('[7/11] Windows engine'),
          UpgradePhase.upgradingEngine);
      expect(upgradePhaseFor('Flutter 3.44.10 • channel stable • https://x'),
          UpgradePhase.verifying);
    });

    test('says nothing about lines that report no progress', () {
      expect(upgradePhaseFor(''), isNull);
      expect(upgradePhaseFor('   '), isNull);
      expect(upgradePhaseFor('Warning: unable to read the cache'), isNull);
    });

    test(
      'reads "Upgrading engine..." as the header it is, not the artifact stage',
      () {
        // The tool prints it *before* downloading the Dart SDK, so treating it
        // as the engine phase would skip two rows the moment the run starts.
        expect(upgradePhaseFor('Upgrading engine...'), isNot(UpgradePhase.upgradingEngine));
      },
    );
  });

  group('intraPhaseFraction', () {
    test('reads git percentages during the download', () {
      expect(
        intraPhaseFraction(
            'Receiving objects:  42% (1234/2929)', UpgradePhase.downloading),
        0.42,
      );
    });

    test('reads the artifact tally during the engine phase', () {
      expect(
        intraPhaseFraction('[3/12] Android SDK', UpgradePhase.upgradingEngine),
        0.25,
      );
    });

    test('has nothing to say about an ordinary line', () {
      expect(
        intraPhaseFraction('Got dependencies.', UpgradePhase.buildingTool),
        isNull,
      );
    });
  });

  group('applyUpgradeLine', () {
    test('advances the stepper and closes off the phase it leaves', () {
      final state = _fold(
        ['Upgrading Flutter to 3.44.10 from 3.44.9', 'Unzipping Dart SDK...'],
        phaseElapsed: const Duration(seconds: 42),
      );
      expect(state.phase, UpgradePhase.extracting);
      expect(state.completed, {UpgradePhase.downloading});
      expect(state.elapsed[UpgradePhase.downloading],
          const Duration(seconds: 42));
      expect(state.statusOf(UpgradePhase.downloading), UpgradePhaseStatus.done);
      expect(state.statusOf(UpgradePhase.extracting), UpgradePhaseStatus.active);
      expect(state.statusOf(UpgradePhase.verifying), UpgradePhaseStatus.pending);
    });

    test('marks a skipped phase done, but with no invented duration', () {
      final state = _fold(['Building flutter tool...']);
      expect(state.phase, UpgradePhase.buildingTool);
      expect(state.completed,
          {UpgradePhase.downloading, UpgradePhase.extracting});
      expect(state.elapsed[UpgradePhase.extracting], isNull);
    });

    test('never walks a phase back when a late line matches an earlier one', () {
      final state = _fold([
        'Building flutter tool...',
        // git chatter can still arrive after the tool build has started.
        'Receiving objects:  10% (1/10)',
      ]);
      expect(state.phase, UpgradePhase.buildingTool);
    });

    test('never lets the bar shrink', () {
      final started = _fold(['Receiving objects:  80% (8/10)']);
      final later = _fold(['Receiving objects:   5% (1/20)'], from: started);
      expect(later.percent, started.percent);
    });

    test('weights the bar by phase and interpolates inside one', () {
      // Download is 40 of the 100 weight units, so half way through it is 20%.
      final half = _fold(['Receiving objects:  50% (5/10)']);
      expect(half.percent, closeTo(0.20, 0.001));
      // Reaching "Building flutter tool" banks download + extract: 55%.
      final tool = _fold(['Building flutter tool...']);
      expect(tool.percent, closeTo(0.55, 0.001));
    });
  });

  group('log buffer', () {
    test('keeps only the last UpgradeProgress.logLimit lines', () {
      var state = const UpgradeProgress();
      for (var i = 0; i < UpgradeProgress.logLimit + 50; i++) {
        state = state.appendLine(_line('line $i'));
      }
      expect(state.lines, hasLength(UpgradeProgress.logLimit));
      expect(state.totalLines, UpgradeProgress.logLimit + 50);
      expect(state.lines.first.text, 'line 50');
      expect(state.lines.last.text, 'line 249');
    });

    test('ignores blank lines', () {
      final state = const UpgradeProgress().appendLine(_line('   '));
      expect(state.lines, isEmpty);
      expect(state.totalLines, 0);
    });

    test('tail returns the newest lines, with stable absolute indices', () {
      var state = const UpgradeProgress();
      for (var i = 0; i < 10; i++) {
        state = state.appendLine(_line('line $i'));
      }
      expect(state.tail(3).map((l) => l.text), ['line 7', 'line 8', 'line 9']);
      expect(state.tailIndex(3, 0), 7);
      expect(state.tailIndex(3, 2), 9);
    });
  });

  group('formatPhaseDuration', () {
    test('reads as seconds under a minute and m/ss over it', () {
      expect(formatPhaseDuration(const Duration(seconds: 8)), '8s');
      expect(formatPhaseDuration(const Duration(seconds: 42)), '42s');
      expect(formatPhaseDuration(const Duration(seconds: 65)), '1m 05s');
      expect(formatPhaseDuration(const Duration(minutes: 12, seconds: 30)),
          '12m 30s');
    });
  });

  group('UpgradeProgress status', () {
    test('nothing spins before the upgrade starts', () {
      const state = UpgradeProgress();
      expect(state.statusOf(UpgradePhase.downloading),
          UpgradePhaseStatus.pending);
    });

    test('a failure marks the phase it stopped in', () {
      const state = UpgradeProgress(
        phase: UpgradePhase.buildingTool,
        completed: {UpgradePhase.downloading, UpgradePhase.extracting},
        finished: true,
        exitCode: 1,
      );
      expect(state.isFailure, isTrue);
      expect(state.statusOf(UpgradePhase.buildingTool),
          UpgradePhaseStatus.failed);
      expect(state.statusOf(UpgradePhase.downloading), UpgradePhaseStatus.done);
    });

    test('a cancelled upgrade is not a failure', () {
      const state = UpgradeProgress(
        phase: UpgradePhase.extracting,
        finished: true,
        cancelled: true,
        exitCode: -1,
      );
      expect(state.isFailure, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.statusOf(UpgradePhase.extracting),
          UpgradePhaseStatus.pending);
    });
  });

  group('UpgradePhaseRow', () {
    testWidgets('pending draws a hollow ring and no duration', (tester) async {
      await tester.pumpWidget(_host(const UpgradePhaseRow(
        phase: UpgradePhase.extracting,
        status: UpgradePhaseStatus.pending,
        elapsed: Duration(seconds: 6),
      )));
      expect(find.text('Extracting files'), findsOneWidget);
      expect(find.byType(AppLoader), findsNothing);
      expect(find.byIcon(FluentIcons.check_mark), findsNothing);
      // A duration only shows once the phase is done.
      expect(find.text('6s'), findsNothing);
    });

    testWidgets('active spins', (tester) async {
      await tester.pumpWidget(_host(const UpgradePhaseRow(
        phase: UpgradePhase.downloading,
        status: UpgradePhaseStatus.active,
      )));
      expect(find.byType(AppLoader), findsOneWidget);
      expect(find.byIcon(FluentIcons.check_mark), findsNothing);
    });

    testWidgets('done ticks and reports its wall clock', (tester) async {
      await tester.pumpWidget(_host(const UpgradePhaseRow(
        phase: UpgradePhase.downloading,
        status: UpgradePhaseStatus.done,
        elapsed: Duration(seconds: 42),
      )));
      expect(find.byIcon(FluentIcons.check_mark), findsOneWidget);
      expect(find.text('42s'), findsOneWidget);
      expect(find.byType(AppLoader), findsNothing);
    });

    testWidgets('done with no recorded duration shows none', (tester) async {
      await tester.pumpWidget(_host(const UpgradePhaseRow(
        phase: UpgradePhase.extracting,
        status: UpgradePhaseStatus.done,
      )));
      expect(find.byIcon(FluentIcons.check_mark), findsOneWidget);
      expect(find.textContaining('s'), findsOneWidget); // the label only
    });

    testWidgets('failed draws the error marker', (tester) async {
      await tester.pumpWidget(_host(const UpgradePhaseRow(
        phase: UpgradePhase.buildingTool,
        status: UpgradePhaseStatus.failed,
      )));
      expect(find.byIcon(FluentIcons.chrome_close), findsOneWidget);
      expect(find.byIcon(FluentIcons.check_mark), findsNothing);
    });
  });

  group('UpgradeStepper', () {
    testWidgets('draws every phase, one of them active', (tester) async {
      const progress = UpgradeProgress(
        phase: UpgradePhase.buildingTool,
        completed: {UpgradePhase.downloading, UpgradePhase.extracting},
        elapsed: {
          UpgradePhase.downloading: Duration(seconds: 42),
          UpgradePhase.extracting: Duration(seconds: 6),
        },
        started: true,
        running: true,
      );
      await tester.pumpWidget(_host(const UpgradeStepper(progress: progress)));

      expect(find.byType(UpgradePhaseRow), findsNWidgets(5));
      expect(find.byIcon(FluentIcons.check_mark), findsNWidgets(2));
      expect(find.byType(AppLoader), findsOneWidget);
      expect(find.text('42s'), findsOneWidget);
      expect(find.text('6s'), findsOneWidget);
      for (final phase in UpgradePhase.values) {
        expect(find.text(phase.label), findsOneWidget);
      }
    });
  });

  group('UpgradeDialogHeader', () {
    testWidgets('reads current → target, and only current without one',
        (tester) async {
      await tester.pumpWidget(_host(const UpgradeDialogHeader(
        progress: UpgradeProgress(started: true, running: true),
        channel: 'stable',
        currentVersion: '3.44.9',
        targetVersion: '3.44.10',
      )));
      expect(find.text('Upgrading Flutter'), findsOneWidget);
      expect(find.text('stable channel'), findsOneWidget);
      expect(find.textContaining('3.44.9 → 3.44.10'), findsOneWidget);

      await tester.pumpWidget(_host(const UpgradeDialogHeader(
        progress: UpgradeProgress(started: true, running: true),
        channel: 'beta',
        currentVersion: '3.44.9',
      )));
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('retitles itself once the upgrade ends', (tester) async {
      await tester.pumpWidget(_host(const UpgradeDialogHeader(
        progress: UpgradeProgress(
          finished: true,
          exitCode: 0,
          completed: {...UpgradePhase.values},
        ),
        channel: 'stable',
        currentVersion: '3.44.9',
        targetVersion: '3.44.10',
      )));
      expect(find.text('Upgrade complete'), findsOneWidget);

      await tester.pumpWidget(_host(const UpgradeDialogHeader(
        progress: UpgradeProgress(finished: true, exitCode: 1),
        channel: 'stable',
        currentVersion: '3.44.9',
      )));
      expect(find.text('Upgrade failed'), findsOneWidget);
    });
  });

  group('UpgradeDialogBody', () {
    Widget body(
      UpgradeProgress progress, {
      bool showDetails = false,
      String? targetVersion = '3.44.10',
      VoidCallback? onToggle,
    }) =>
        _host(UpgradeDialogBody(
          progress: progress,
          targetVersion: targetVersion,
          showDetails: showDetails,
          onToggleDetails: onToggle ?? () {},
        ));

    testWidgets('hides the log behind Show details', (tester) async {
      const progress = UpgradeProgress(started: true, running: true);
      await tester.pumpWidget(body(progress));
      expect(find.text('Show details'), findsOneWidget);
      expect(find.byType(UpgradeDetailsLog), findsNothing);

      await tester.pumpWidget(body(progress, showDetails: true));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Hide details'), findsOneWidget);
      expect(find.byType(UpgradeDetailsLog), findsOneWidget);
    });

    testWidgets('the toggle calls back', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(body(
        const UpgradeProgress(started: true, running: true),
        onToggle: () => toggled++,
      ));
      await tester.tap(find.text('Show details'));
      expect(toggled, 1);
    });

    testWidgets('shows the phase, the rounded percentage and the bar',
        (tester) async {
      final progress = _fold(['Receiving objects:  50% (5/10)']);
      await tester.pumpWidget(body(progress));
      await tester.pump(const Duration(milliseconds: 600));
      // The label above the bar names the same phase the stepper row does.
      expect(find.text('Downloading archive'), findsNWidgets(2));
      expect(find.text('20%'), findsOneWidget);
    });

    testWidgets('reports the finished version, at 100%', (tester) async {
      const progress = UpgradeProgress(
        phase: UpgradePhase.verifying,
        completed: {...UpgradePhase.values},
        percent: 1,
        finished: true,
        exitCode: 0,
      );
      await tester.pumpWidget(body(progress));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Flutter 3.44.10 is ready'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('a failure shows its summary next to the stopped bar',
        (tester) async {
      const progress = UpgradeProgress(
        phase: UpgradePhase.buildingTool,
        completed: {UpgradePhase.downloading, UpgradePhase.extracting},
        percent: 0.55,
        finished: true,
        exitCode: 1,
        errorSummary: 'Error: pub upgrade failed',
        lines: [CommandOutputLine('Error: pub upgrade failed', isError: true)],
      );
      await tester.pumpWidget(body(progress, showDetails: true));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Error: pub upgrade failed'), findsNWidgets(2)); // label + log
      expect(find.text('55%'), findsOneWidget);
      expect(find.byIcon(FluentIcons.chrome_close), findsOneWidget);
    });

    testWidgets('the log shows only the newest few lines', (tester) async {
      var progress = const UpgradeProgress(started: true, running: true);
      for (var i = 0; i < 20; i++) {
        progress = progress.appendLine(_line('line $i'));
      }
      await tester.pumpWidget(body(progress, showDetails: true));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('line 19'), findsOneWidget);
      expect(
        find.text('line ${20 - UpgradeDetailsLog.visibleLines}'),
        findsOneWidget,
      );
      expect(
        find.text('line ${19 - UpgradeDetailsLog.visibleLines}'),
        findsNothing,
      );
    });

    testWidgets('lays out at the dialog width without overflowing',
        (tester) async {
      var progress = _fold([
        'Upgrading Flutter to 3.44.10 from 3.44.9',
        'Unzipping Dart SDK...',
        'Building flutter tool...',
        'Running pub upgrade...',
      ]);
      progress = progress.appendLine(_line(
        'A very long line of tool output that would run off the end of the '
        'recessed log box if it were ever allowed to wrap or overflow',
      ));
      await tester.pumpWidget(body(progress, showDetails: true));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  });
}
