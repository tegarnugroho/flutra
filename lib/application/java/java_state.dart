part of 'java_cubit.dart';

enum JavaStatus { initial, loading, ready, failure }

/// What a JDK is in the middle of, which is what its button says while it runs.
enum JdkTask {
  settingFlutter,
  settingJavaHome;

  String get label => switch (this) {
    JdkTask.settingFlutter => 'Setting…',
    JdkTask.settingJavaHome => 'Writing…',
  };
}

/// Immutable state for the Java screen.
class JavaState extends Equatable {
  const JavaState({
    this.status = JavaStatus.initial,
    this.jdks = const [],
    this.tasks = const {},
    this.flutterJdkDir,
    this.javaHome,
    this.pathJdk,
    this.flutterVersion,
    this.errorMessage,
  });

  final JavaStatus status;

  /// Every JDK found, deduped, best-known source first.
  final List<Jdk> jdks;

  /// In-flight work per JDK path.
  final Map<String, JdkTask> tasks;

  /// `flutter config --jdk-dir`, or null when Flutter uses the system default.
  final String? flutterJdkDir;

  final String? javaHome;

  /// The JDK root owning the first `java` on PATH.
  final String? pathJdk;

  /// The installed Flutter version, for the Gradle compatibility hint. Null
  /// when the app has not read it, which simply means no hint.
  final String? flutterVersion;

  final String? errorMessage;

  bool get isLoading => status == JavaStatus.loading;

  /// True until the first scan settles, so the screen shows its skeleton from
  /// the very first frame rather than flashing the empty state.
  bool get isFirstLoad =>
      jdks.isEmpty &&
      (status == JavaStatus.initial || status == JavaStatus.loading);

  bool isBusy(String path) => tasks.containsKey(path);

  JdkTask? taskFor(String path) => tasks[path];

  /// The JDK a build will actually use, and what decided that.
  ActiveJdk? get active => resolveActiveJdk(
    jdks,
    flutterJdkDir: flutterJdkDir,
    javaHome: javaHome,
    pathJdk: pathJdk,
  );

  /// Whether Flutter has been told which JDK to use, rather than falling back
  /// to whatever the system offers.
  bool get configuredForFlutter =>
      flutterJdkDir != null && flutterJdkDir!.trim().isNotEmpty;

  /// True for the tile Flutter builds will use.
  bool isActiveForFlutter(Jdk jdk) =>
      configuredForFlutter && samePath(jdk.path, flutterJdkDir!);

  /// One line about a JDK the toolchain cannot use, or null when there is
  /// nothing worth saying.
  String? get compatibilityWarning => jdkGradleWarning(
    jdkMajor: active?.jdk.major,
    flutterVersion: flutterVersion,
  );

  /// `4 JDKs · JDK 17 active`, dropping the second half when nothing is.
  String get countLabel {
    final total = '${jdks.length} JDK${jdks.length == 1 ? '' : 's'}';
    final current = active;
    return current == null ? total : '$total · ${current.jdk.displayName} in use';
  }

  JavaState copyWith({
    JavaStatus? status,
    List<Jdk>? jdks,
    Map<String, JdkTask>? tasks,
    String? flutterJdkDir,
    bool clearFlutterJdkDir = false,
    String? javaHome,
    String? pathJdk,
    String? flutterVersion,
    String? errorMessage,
    bool clearError = false,
  }) {
    return JavaState(
      status: status ?? this.status,
      jdks: jdks ?? this.jdks,
      tasks: tasks ?? this.tasks,
      flutterJdkDir: clearFlutterJdkDir
          ? null
          : (flutterJdkDir ?? this.flutterJdkDir),
      javaHome: javaHome ?? this.javaHome,
      pathJdk: pathJdk ?? this.pathJdk,
      flutterVersion: flutterVersion ?? this.flutterVersion,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    jdks,
    tasks,
    flutterJdkDir,
    javaHome,
    pathJdk,
    flutterVersion,
    errorMessage,
  ];
}
