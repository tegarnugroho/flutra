import 'package:bloc/bloc.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:injectable/injectable.dart';

/// Holds the active [ThemeMode] and toggles between light and dark.
///
/// Registered as a singleton so the whole app shares one theme selection.
@singleton
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.dark);

  void setMode(ThemeMode mode) => emit(mode);

  void toggle() =>
      emit(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}
