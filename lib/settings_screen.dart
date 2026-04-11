import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = 'v${info.version} (${info.buildNumber})';
      });
    }
  }

  Future<void> _launchGithubUrl() async {
    final Uri url = Uri.parse('https://github.com/rajvishvakarma088-star/GallerySnoop');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch \$url');
    }
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        content: Text(
          'Donation Coming Soon! Thank you \u2764\uFE0F',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = settings.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final topBarColor = settings.getTopBarColor(isDark).withValues(alpha: 0.85);

    final overlayStyle = (isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          color: colorScheme.onSurface,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: topBarColor.withValues(alpha: isDark ? 0.75 : 0.82),
                border: Border(
                  bottom: BorderSide(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.1 : 0.06),
                    width: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        systemOverlayStyle: overlayStyle,
      ),
      body: Stack(
        children: [
          // 1. Base Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: settings.getBackgroundGradient(isDark),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // 2. Decorative Orbs
          Positioned(
            top: -80,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6)
                      .withValues(alpha: isDark ? 0.05 : 0.08),
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: 80,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFC4B5FD)
                      .withValues(alpha: isDark ? 0.03 : 0.12),
                ),
              ),
            ),
          ),
          // 3. Content
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 104, 20, 32),
              physics: const BouncingScrollPhysics(),
              children: [
                // App Info Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              settings.amoledMode ? const Color(0xFF0A0A0A) : const Color(0xFF1E1E1E),
                              settings.amoledMode ? const Color(0xFF121212) : const Color(0xFF252525),
                            ]
                          : [
                              const Color(0xFFFFFFFF),
                              const Color(0xFFF4F4F4),
                            ],
                    ),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.1 : 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Gallery',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Text(
                            _version,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'by Raj Vishvakarma',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        // Donate Button
                        Expanded(
                          child: Material(
                            color: isDark ? const Color(0xFF4C427B).withOpacity(0.6) : Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: () => _showComingSoon(context),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF5A4C9B) : const Color(0xFFA284EE),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.volunteer_activism_rounded, size: 20, color: isDark ? const Color(0xFFAEB2F6) : const Color(0xFF5A38E6)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Donate',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isDark ? const Color(0xFFAEB2F6) : const Color(0xFF5A38E6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Github Button
                        Expanded(
                          child: Material(
                            color: isDark ? const Color(0xFFB099D7) : const Color(0xFF8B5CF6),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: _launchGithubUrl,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.code_rounded, size: 20, color: isDark ? const Color(0xFF1E1E1E) : Colors.white),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Github',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Settings Categories
              Container(
                decoration: BoxDecoration(
                  color: isDark 
                      ? (settings.amoledMode ? const Color(0xFF080808) : const Color(0xFF171321)) 
                      : const Color(0xFFF9F7FA),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.palette_rounded,
                      title: 'Dark Mode',
                      subtitle: 'Switch between light, dark, or system theme',
                      iconColor: isDark ? const Color(0xFF9080CF) : const Color(0xFF6F3CD2),
                      iconBgColor: isDark ? const Color(0xFF282542) : const Color(0xFFEDE4FF),
                      trailing: DropdownButton<ThemeMode>(
                        value: settings.themeMode,
                        dropdownColor: colorScheme.surface,
                        underline: const SizedBox.shrink(),
                        onChanged: (ThemeMode? newValue) {
                          if (newValue != null) {
                            ref.read(settingsProvider.notifier).updateThemeMode(newValue);
                          }
                        },
                        items: const [
                          DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                          DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                        ],
                      ),
                      onTap: () {},
                    ),
                    if (isDark)
                      _buildSettingsTile(
                        context: context,
                        icon: Icons.contrast_rounded,
                        title: 'AMOLED Mode',
                        subtitle: 'Use pure black backgrounds',
                        iconColor: const Color(0xFFCA9DFD),
                        iconBgColor: const Color(0xFF2D2342),
                        trailing: Switch(
                          value: settings.amoledMode,
                          onChanged: (value) {
                            ref.read(settingsProvider.notifier).toggleAmoledMode(value);
                          },
                        ),
                        onTap: () {},
                      ),
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Show Hidden Media',
                      subtitle: 'Display hidden files and folders',
                      iconColor: isDark ? const Color(0xFFAFA2CC) : const Color(0xFF7060A0),
                      iconBgColor: isDark ? const Color(0xFF2A273A) : const Color(0xFFF2EFFF),
                      trailing: Switch(
                        value: settings.showHidden,
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).toggleShowHidden(value);
                        },
                      ),
                      onTap: () {},
                    ),
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.animation_rounded,
                      title: 'Animations',
                      subtitle: 'Enable UI transitions and effects',
                      iconColor: isDark ? const Color(0xFFCA9DFD) : const Color(0xFFA151EA),
                      iconBgColor: isDark ? const Color(0xFF2D2342) : const Color(0xFFF6E7FE),
                      trailing: Switch(
                        value: settings.animationsEnabled,
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).toggleAnimations(value);
                        },
                      ),
                      onTap: () {},
                    ),
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.auto_awesome_mosaic_rounded,
                      title: 'Rounded Thumbnails',
                      subtitle: 'Use smooth curves for media grid',
                      iconColor: const Color(0xFFCA9DFD),
                      iconBgColor: isDark ? const Color(0xFF2D2342) : const Color(0xFFF6E7FE),
                      trailing: Switch(
                        value: settings.roundedThumbnails,
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).toggleRoundedThumbnails(value);
                        },
                      ),
                      onTap: () {},
                    ),
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.refresh_rounded,
                      title: 'Pull to Refresh',
                      subtitle: 'Enable elastic rubber-band refresh',
                      iconColor: isDark ? const Color(0xFF9080CF) : const Color(0xFF6F3CD2),
                      iconBgColor: isDark ? const Color(0xFF282542) : const Color(0xFFEDE4FF),
                      trailing: Switch(
                        value: settings.pullToRefreshEnabled,
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).togglePullToRefresh(value);
                        },
                      ),
                      onTap: () {},
                    ),
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.info_outline_rounded,
                      title: 'Show File Info',
                      subtitle: 'Display size and date on thumbnails',
                      iconColor: isDark ? const Color(0xFFEEA297) : const Color(0xFFDD6153),
                      iconBgColor: isDark ? const Color(0xFF322629) : const Color(0xFFFCE9E6),
                      trailing: Switch(
                        value: settings.showFileSize,
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).toggleShowFileSize(value);
                          ref.read(settingsProvider.notifier).toggleShowFileDate(value);
                        },
                      ),
                      onTap: () {},
                    ),
                    _buildSettingsTile(
                      context: context,
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI Smart Search',
                      subtitle: 'Enable local AI object and face detection',
                      iconColor: const Color(0xFFEEA297),
                      iconBgColor: isDark ? const Color(0xFF322629) : const Color(0xFFFCE9E6),
                      trailing: Switch(
                        value: settings.aiTagging,
                        onChanged: (value) {
                          ref.read(settingsProvider.notifier).toggleAiTagging(value);
                        },
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
