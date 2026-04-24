import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'gallery_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/settings_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Keep a larger decoded-image window so recently viewed thumbnails stay hot
  // when the user scrolls back, closer to native gallery app behavior.
  PaintingBinding.instance.imageCache.maximumSize = 1400;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 320 << 20;

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(Brightness brightness, SettingsState settings) {
    final isDark = brightness == Brightness.dark;
    final amoled = isDark && settings.amoledMode;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: settings.accentColor,
      brightness: brightness,
    );

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark
          ? (amoled ? Colors.black : const Color(0xFF0D0D0D))
          : const Color(0xFFF9FAFB),
      canvasColor: isDark 
          ? (amoled ? Colors.black : const Color(0xFF0D0D0D)) 
          : const Color(0xFFF9FAFB),
      cardColor: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFECE1FF).withValues(alpha: 0.76),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A1A1A),
        systemOverlayStyle: overlayStyle,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      dividerColor: Colors.white.withOpacity(isDark ? 0.16 : 0.5),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Photic Gallery',
      theme: _buildTheme(Brightness.light, settings),
      darkTheme: _buildTheme(Brightness.dark, settings),
      themeMode: settings.themeMode,
      home: const GalleryScreen(),
    );
  }
}
