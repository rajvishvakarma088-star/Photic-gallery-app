import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final ThemeMode themeMode;
  final Color accentColor;
  final bool amoledMode;
  final bool showHidden;
  final bool animationsEnabled;
  final String sortOrder;
  final double gridSize;
  final bool showFileSize;
  final bool showFileDate;
  final bool roundedThumbnails;
  final bool aiTagging;
  final bool smartGrouping;
  final bool duplicateDetection;
  final bool pullToRefreshEnabled;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.accentColor = const Color(0xFF8B5CF6),
    this.amoledMode = true,
    this.showHidden = false,
    this.animationsEnabled = true,
    this.sortOrder = 'date_desc',
    this.gridSize = 3.0,
    this.showFileSize = false,
    this.showFileDate = false,
    this.roundedThumbnails = true,
    this.aiTagging = true,
    this.smartGrouping = false,
    this.duplicateDetection = false,
    this.pullToRefreshEnabled = true,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    Color? accentColor,
    bool? amoledMode,
    bool? showHidden,
    bool? animationsEnabled,
    String? sortOrder,
    double? gridSize,
    bool? showFileSize,
    bool? showFileDate,
    bool? roundedThumbnails,
    bool? aiTagging,
    bool? smartGrouping,
    bool? duplicateDetection,
    bool? pullToRefreshEnabled,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      amoledMode: amoledMode ?? this.amoledMode,
      showHidden: showHidden ?? this.showHidden,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
      gridSize: gridSize ?? this.gridSize,
      showFileSize: showFileSize ?? this.showFileSize,
      showFileDate: showFileDate ?? this.showFileDate,
      roundedThumbnails: roundedThumbnails ?? this.roundedThumbnails,
      aiTagging: aiTagging ?? this.aiTagging,
      smartGrouping: smartGrouping ?? this.smartGrouping,
      duplicateDetection: duplicateDetection ?? this.duplicateDetection,
      pullToRefreshEnabled: pullToRefreshEnabled ?? this.pullToRefreshEnabled,
    );
  }
  bool isDark(BuildContext context) {
    if (themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return themeMode == ThemeMode.dark;
  }

  List<Color> getBackgroundGradient(bool isDark) {
    if (isDark) {
      return amoledMode
          ? const [Color(0xFF000000), Color(0xFF020202), Color(0xFF050505)]
          : const [Color(0xFF050505), Color(0xFF080808), Color(0xFF0C0C0C)];
    }
    return const [Color(0xFFFFFFFF), Color(0xFFF9F9F9), Color(0xFFF0F0F0)];
  }

  Color getBottomBarColor(bool isDark) {
    if (isDark) {
      return amoledMode ? Colors.black : const Color(0xFF080808);
    }
    return Colors.white;
  }

  Color getTopBarColor(bool isDark) {
    if (isDark) {
      return amoledMode ? Colors.black : const Color(0xFF080808);
    }
    return const Color(0xFFF1E8FF);
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _themeModeKey = 'settings_theme_mode';
  static const _amoledModeKey = 'settings_amoled_mode';
  static const _accentColorKey = 'settings_accent_color';
  static const _showHiddenKey = 'settings_show_hidden';
  static const _animationsEnabledKey = 'settings_animations_enabled';
  static const _gridSizeKey = 'settings_grid_size';
  static const _pullToRefreshKey = 'settings_pull_to_refresh';

  SharedPreferences? _prefs;

  @override
  SettingsState build() {
    // Initial state before SharedPreferences loads
    _loadFromPrefs();
    return const SettingsState();
  }

  Future<void> _loadFromPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (_prefs == null) return;
    
    final themeModeIndex = _prefs!.getInt(_themeModeKey) ?? ThemeMode.system.index;
    final amoledMode = _prefs!.getBool(_amoledModeKey) ?? true;
    final accentValue = _prefs!.getInt(_accentColorKey) ?? 0xFF8B5CF6;
    final showHidden = _prefs!.getBool(_showHiddenKey) ?? false;
    final animationsEnabled = _prefs!.getBool(_animationsEnabledKey) ?? true;
    final gridSize = _prefs!.getDouble(_gridSizeKey) ?? 3.0;
    final pullToRefresh = _prefs!.getBool(_pullToRefreshKey) ?? true;

    state = state.copyWith(
      themeMode: ThemeMode.values[themeModeIndex],
      amoledMode: amoledMode,
      accentColor: Color(accentValue),
      showHidden: showHidden,
      animationsEnabled: animationsEnabled,
      gridSize: gridSize,
      pullToRefreshEnabled: pullToRefresh,
    );
  }

  void updateThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs?.setInt(_themeModeKey, mode.index);
  }

  void toggleAmoledMode(bool isAmoled) {
    state = state.copyWith(amoledMode: isAmoled);
    _prefs?.setBool(_amoledModeKey, isAmoled);
  }

  void updateAccentColor(Color color) {
    state = state.copyWith(accentColor: color);
    _prefs?.setInt(_accentColorKey, color.value);
  }

  void toggleShowHidden(bool show) {
    state = state.copyWith(showHidden: show);
    _prefs?.setBool(_showHiddenKey, show);
  }

  void toggleAnimations(bool enabled) {
    state = state.copyWith(animationsEnabled: enabled);
    _prefs?.setBool(_animationsEnabledKey, enabled);
  }

  void updateGridSize(double size) {
    state = state.copyWith(gridSize: size);
    _prefs?.setDouble(_gridSizeKey, size);
  }

  void togglePullToRefresh(bool enabled) {
    state = state.copyWith(pullToRefreshEnabled: enabled);
    _prefs?.setBool(_pullToRefreshKey, enabled);
  }

  void toggleAiTagging(bool enabled) {
    state = state.copyWith(aiTagging: enabled);
  }

  void toggleSmartGrouping(bool enabled) {
    state = state.copyWith(smartGrouping: enabled);
  }

  void toggleDuplicateDetection(bool enabled) {
    state = state.copyWith(duplicateDetection: enabled);
  }

  void toggleRoundedThumbnails(bool enabled) {
    state = state.copyWith(roundedThumbnails: enabled);
  }

  void toggleShowFileSize(bool enabled) {
    state = state.copyWith(showFileSize: enabled);
  }

  void toggleShowFileDate(bool enabled) {
    state = state.copyWith(showFileDate: enabled);
  }

  void toggleThemeContext(BuildContext context) {
    final Brightness systemBrightness = MediaQuery.platformBrightnessOf(context);
    final bool isDark = state.themeMode == ThemeMode.system 
        ? systemBrightness == Brightness.dark 
        : state.themeMode == ThemeMode.dark;
    updateThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  () => SettingsNotifier(),
);
