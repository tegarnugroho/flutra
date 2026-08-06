import 'package:flutra/application/flutter_sdk/flutter_sdk_cubit.dart';
import 'package:flutra/domain/entities/flutter_release.dart';
import 'package:flutra/domain/entities/flutter_sdk_info.dart';
import 'package:flutra/presentation/flutter_sdk/widgets/sdk_identity_panel.dart';
import 'package:flutra/presentation/flutter_sdk/widgets/version_tile.dart';
import 'package:flutra/presentation/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => FluentApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.dark,
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SizedBox(width: 900, child: child),
  ),
);

const _info = FlutterSdkInfo(
  version: '3.44.1',
  channel: 'stable',
  dartVersion: '3.12.1',
  frameworkRevision: '924134a44c9e1f0e2a3b4c5d6e7f8091a2b3c4d5',
  sdkPath: r'C:\Dev\SDK\flutter',
  isGitRepo: true,
);

FlutterRelease _release(
  String version, {
  String? dart,
  String hash = 'abc',
  DateTime? date,
}) => FlutterRelease(
  hash: hash,
  channel: 'stable',
  version: version,
  dartSdkVersion: dart,
  releaseDate: date ?? DateTime(2026, 8, 6),
);

Widget _tile({
  required FlutterRelease release,
  bool isCurrent = false,
  bool expanded = false,
  String? dartBadge,
  List<String> changelog = const [],
  VoidCallback? onSwitch,
  ValueChanged<int>? onOpenPullRequest,
  VoidCallback? onOpenGitHub,
}) => VersionTile(
  release: release,
  isCurrent: isCurrent,
  expanded: expanded,
  highlighted: false,
  dartBadge: dartBadge,
  onToggle: () {},
  onSwitch: onSwitch ?? () {},
  loadChangelog: () async => changelog,
  onOpenGitHub: onOpenGitHub ?? () {},
  onOpenPullRequest: onOpenPullRequest ?? (_) {},
);

void main() {
  group('SDK identity panel', () {
    testWidgets('offers Add to PATH with a caption when PATH is missing',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SdkIdentityPanel(
            info: _info,
            updateAvailable: false,
            latestKnown: true,
            latestVersion: '3.44.1',
            pathStatus: SdkPathStatus.absent,
            onAddToPath: () {},
            onRevealLatest: () {},
          ),
        ),
      );

      expect(find.text('Add to PATH'), findsOneWidget);
      expect(find.text('Not detected in system PATH'), findsOneWidget);
      expect(find.text('In system PATH'), findsNothing);
    });

    testWidgets('confirms quietly, with no button, once PATH holds the SDK',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SdkIdentityPanel(
            info: _info,
            updateAvailable: false,
            latestKnown: true,
            latestVersion: '3.44.1',
            pathStatus: SdkPathStatus.present,
            onAddToPath: () {},
            onRevealLatest: () {},
          ),
        ),
      );

      expect(find.text('In system PATH'), findsOneWidget);
      expect(find.text('Add to PATH'), findsNothing);
    });

    testWidgets('says nothing at all while the PATH read is unresolved',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SdkIdentityPanel(
            info: _info,
            updateAvailable: false,
            latestKnown: true,
            latestVersion: null,
            pathStatus: SdkPathStatus.unknown,
            onAddToPath: () {},
            onRevealLatest: () {},
          ),
        ),
      );

      expect(find.text('Add to PATH'), findsNothing);
      expect(find.text('In system PATH'), findsNothing);
    });

    testWidgets('the update pill jumps to the newest release', (tester) async {
      var revealed = 0;
      await tester.pumpWidget(
        _host(
          SdkIdentityPanel(
            info: _info,
            updateAvailable: true,
            latestKnown: true,
            latestVersion: '3.45.0',
            pathStatus: SdkPathStatus.present,
            onAddToPath: () {},
            onRevealLatest: () => revealed++,
          ),
        ),
      );

      expect(find.text('stable · latest'), findsNothing);
      await tester.tap(find.text('update available'));
      expect(revealed, 1);
    });

    testWidgets('an up-to-date SDK gets the channel pill instead',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SdkIdentityPanel(
            info: _info,
            updateAvailable: false,
            latestKnown: true,
            latestVersion: '3.44.1',
            pathStatus: SdkPathStatus.present,
            onAddToPath: () {},
            onRevealLatest: () {},
          ),
        ),
      );

      expect(find.text('stable · latest'), findsOneWidget);
      expect(find.text('update available'), findsNothing);
    });

    testWidgets('claims nothing about "latest" when it cannot be compared',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SdkIdentityPanel(
            info: _info,
            updateAvailable: false,
            // No HEAD to compare (not a git checkout) or no index entry.
            latestKnown: false,
            latestVersion: null,
            pathStatus: SdkPathStatus.present,
            onAddToPath: () {},
            onRevealLatest: () {},
          ),
        ),
      );

      expect(find.text('stable · latest'), findsNothing);
      expect(find.text('stable'), findsOneWidget);
    });
  });

  group('version tile', () {
    testWidgets('the current version is labelled and never offers a switch',
        (tester) async {
      await tester.pumpWidget(
        _host(
          _tile(
            release: _release('3.44.1', dart: '3.12.1'),
            isCurrent: true,
            expanded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('installed · in use'), findsOneWidget);
      expect(find.text('Switch'), findsNothing);
    });

    testWidgets('Switch appears only once a non-current tile is open',
        (tester) async {
      await tester.pumpWidget(
        _host(_tile(release: _release('3.43.0', dart: '3.12.0'))),
      );
      expect(find.text('Switch'), findsNothing);

      await tester.pumpWidget(
        _host(_tile(release: _release('3.43.0', dart: '3.12.0'),
            expanded: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Switch'), findsOneWidget);
    });

    testWidgets('the meta line carries the Dart version and release date',
        (tester) async {
      await tester.pumpWidget(
        _host(
          _tile(
            release: _release(
              '3.43.0',
              dart: '3.12.0',
              date: DateTime(2026, 3, 12),
            ),
          ),
        ),
      );

      expect(find.text('Dart 3.12.0 · Mar 12, 2026'), findsOneWidget);
    });

    testWidgets('a Dart minor change is badged', (tester) async {
      await tester.pumpWidget(
        _host(
          _tile(
            release: _release('3.40.0', dart: '3.11.0'),
            dartBadge: '3.11.0',
          ),
        ),
      );

      expect(find.text('Dart 3.11.0'), findsOneWidget);
    });

    testWidgets('an open tile renders categorised, stripped release notes',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            release: _release('3.43.0', dart: '3.12.0'),
            expanded: true,
            changelog: const [
              '[CP-stable][Android] Fix black screen on resume (#189605)',
              'Update CHANGELOG.md (#189700)',
            ],
            onOpenPullRequest: (_) => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Release notes'), findsOneWidget);
      expect(find.text('android'), findsOneWidget);
      expect(find.text('docs'), findsOneWidget);
      // The bracket prefix is gone from what is read, but the PR is a link.
      expect(find.textContaining('[CP-stable]'), findsNothing);
      await tester.tap(find.text('#189605'));
      expect(opened, 1);

      // The count only exists once the notes have loaded — the release index
      // does not publish it.
      expect(find.textContaining('2 commits'), findsOneWidget);
    });

    testWidgets('empty notes say so and still link out', (tester) async {
      var changelogOpened = 0;
      await tester.pumpWidget(
        _host(
          _tile(
            release: _release('3.43.0'),
            expanded: true,
            onOpenGitHub: () => changelogOpened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Release notes unavailable'), findsOneWidget);
      await tester.tap(find.text('Full changelog ↗'));
      expect(changelogOpened, 1);
    });
  });

  group('relativeAge', () {
    final now = DateTime(2026, 8, 6);

    test('reads coarsely, because the exact date is on the same line', () {
      expect(relativeAge(now, now), 'today');
      expect(relativeAge(now.subtract(const Duration(days: 1)), now),
          'yesterday');
      expect(relativeAge(now.subtract(const Duration(days: 4)), now),
          '4 days ago');
      expect(relativeAge(now.subtract(const Duration(days: 9)), now),
          'a week ago');
      expect(relativeAge(now.subtract(const Duration(days: 21)), now),
          '3 weeks ago');
      expect(relativeAge(now.subtract(const Duration(days: 200)), now),
          '6 months ago');
      expect(relativeAge(now.subtract(const Duration(days: 400)), now),
          'a year ago');
    });
  });

  group('dartMinor', () {
    test('keeps the minor, drops the patch', () {
      expect(dartMinor(_release('3.44.1', dart: '3.12.1')), '3.12');
      expect(dartMinor(_release('3.44.1', dart: '3.13.0 (build 3.13.0-282)')),
          '3.13');
      expect(dartMinor(_release('3.44.1')), isNull);
    });
  });
}
