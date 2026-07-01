import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

/// The application-wide service locator.
final GetIt getIt = GetIt.instance;

/// Registers every `@injectable`-annotated dependency.
///
/// Call once at startup, before running the app.
@InjectableInit()
void configureDependencies() => getIt.init();
