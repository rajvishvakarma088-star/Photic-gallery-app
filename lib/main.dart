import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'gallery_screen.dart';

void main() {
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
      seedColor: const Color(0xFF7C6EE6),
      brightness: brightness,
    );

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: const Color(0xFF120C24),
            systemNavigationBarColor: const Color(0xFF120C24),
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: const Color(0xFFF7F4FF),
            systemNavigationBarColor: const Color(0xFFF7F4FF),
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      cardColor: isDark
          ? Colors.white.withOpacity(0.08)
          : Colors.white.withOpacity(0.62),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0x22181430) : const Color(0xCCFFFFFF),
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        systemOverlayStyle: overlayStyle,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isDark ? const Color(0xCC181430) : const Color(0xD9FFFFFF),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: isDark
            ? const Color(0xFF7C6EE6).withOpacity(0.26)
            : const Color(0xFFD9D0FF).withOpacity(0.7),
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
