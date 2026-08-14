import 'package:flutra/domain/entities/jdk.dart';
import 'package:flutra/domain/entities/tool_status.dart';
import 'package:flutra/infrastructure/repositories/environment_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

Jdk _jdk({
  required JdkSource source,
  String? version = '17.0.20',
  JdkValidity validity = JdkValidity.valid,
  String path = '/home/dev/.local/share/com.flutra/jdks/temurin-17.0.20',
}) => Jdk(
  path: path,
  source: source,
  validity: validity,
  version: version,
  vendor: 'Eclipse Adoptium',
);

void main() {
  group('javaStatusOf', () {
    test('a Flutra-managed JDK set in flutter config reads as installed', () {
      // The reported bug: the Java page listed this one as active while the
      // Dashboard said "not detected", because the Dashboard only ever looked at
      // JAVA_HOME and PATH — and a managed JDK is on neither.
      final status = javaStatusOf(
        ActiveJdk(
          _jdk(source: JdkSource.managed),
          ActiveJdkSource.flutterConfig,
        ),
      );

      expect(status.kind, ToolKind.java);
      expect(status.state, ToolState.installed);
      expect(status.isInstalled, isTrue);
      expect(
        status.version,
        '17.0.20',
        reason: 'the row shows a version like the Flutter row does',
      );
      expect(
        status.path,
        contains('com.flutra'),
        reason: 'the managed path, not whatever PATH resolves',
      );
    });

    test('the row says where the JDK came from and what activated it', () {
      final status = javaStatusOf(
        ActiveJdk(
          _jdk(source: JdkSource.managed),
          ActiveJdkSource.flutterConfig,
        ),
      );

      expect(status.detail, contains('Flutra'));
      expect(status.detail, contains('flutter config'));
    });

    test('a system JDK on JAVA_HOME is just as detected', () {
      // Priority 2: nothing managed is active, so the fallback answers — and it
      // must be green, not a lesser state.
      final status = javaStatusOf(
        ActiveJdk(
          _jdk(source: JdkSource.registry, path: r'C:\Program Files\Java\jdk-21'),
          ActiveJdkSource.javaHome,
        ),
      );

      expect(status.state, ToolState.installed);
      expect(status.detail, contains('JAVA_HOME'));
    });

    test('a JRE is an error, not a detected JDK', () {
      // It resolves, it runs, and it cannot compile. Reporting the toolchain as
      // ready here means the Gradle failure arrives later and further away.
      final status = javaStatusOf(
        ActiveJdk(
          _jdk(source: JdkSource.disk, validity: JdkValidity.jreOnly),
          ActiveJdkSource.path,
        ),
      );

      expect(status.state, ToolState.error);
      expect(status.isInstalled, isFalse);
      expect(status.detail, contains('JRE'));
    });

    test('a JDK whose version could not be read still counts as installed', () {
      final status = javaStatusOf(
        ActiveJdk(_jdk(source: JdkSource.manual, version: null),
            ActiveJdkSource.javaHome),
      );

      expect(status.state, ToolState.installed);
      expect(status.version, isNull);
    });
  });

  group('the banner count follows the row', () {
    // The "N tools not detected" line counts missing and error rows, so fixing
    // the Java row is what decrements it. Pinned here because the count is
    // derived, and a row that silently stopped being counted would be invisible.
    bool broken(ToolStatus status) =>
        status.state == ToolState.missing || status.state == ToolState.error;

    test('a managed JDK stops being counted as broken', () {
      final fixed = javaStatusOf(
        ActiveJdk(
          _jdk(source: JdkSource.managed),
          ActiveJdkSource.flutterConfig,
        ),
      );
      const missing = ToolStatus(
        kind: ToolKind.java,
        state: ToolState.missing,
      );

      expect(broken(missing), isTrue);
      expect(broken(fixed), isFalse);
    });
  });
}
