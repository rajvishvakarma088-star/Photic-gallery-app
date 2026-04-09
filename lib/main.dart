import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'gallery_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  PaintingBinding.instance.imageCache.maximumSize = 320;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 << 20;

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6F4DFF),
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
      scaffoldBackgroundColor: Colors.transparent,
      cardColor: isDark
          ? Colors.white.withOpacity(0.08)
          : const Color(0xFFEFE2FF).withOpacity(0.72),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0x22181430) : const Color(0xD9EEE2FF),
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        systemOverlayStyle: overlayStyle,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isDark ? const Color(0xCC181430) : const Color(0xD9EEE3FF),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: isDark
            ? const Color(0xFF7C6EE6).withOpacity(0.26)
            : const Color(0xFFCEB5FF).withOpacity(0.84),
        labelTextStyle:
            WidgetStatePropertyAll(TextStyle(color: colorScheme.onSurface)),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      dividerColor: Colors.white.withOpacity(isDark ? 0.16 : 0.5),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: themeProvider.themeMode,
          home: const GalleryScreen(),
        );
      },
    );
  }
}
