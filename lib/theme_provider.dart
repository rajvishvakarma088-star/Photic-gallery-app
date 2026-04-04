import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;

  bool isDark(BuildContext context) {
    if (themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return themeMode == ThemeMode.dark;
  }

  void toggleTheme(BuildContext context) {
    // Determine effective brightness (even if themeMode is system)
    final currentlyDark = isDark(context);
    themeMode = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
