import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'glass_container.dart';
import 'services/screenshot_protection_service.dart';
import 'services/vault_database.dart';
import 'services/vault_service.dart';
import 'providers/settings_provider.dart';
import 'utils/fast_page_scroll_physics.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> with WidgetsBindingObserver {
  final VaultService vaultService = VaultService.instance;
  List<VaultItem> _items = [];
  bool _isLoading = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _hasChanged = false;
  int _selectedTab = 0;
  Set<String> _selectedItemIds = {};
  bool _isSelectionMode = false;

  List<VaultItem> get _photos => _items
      .where((item) => item.mediaType == VaultMediaType.photo)
      .toList(growable: false);
  List<VaultItem> get _videos => _items
      .where((item) => item.mediaType == VaultMediaType.video)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ScreenshotProtectionService.setProtected(true));
    unawaited(_loadVault());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(vaultService.lock());
    unawaited(ScreenshotProtectionService.setProtected(false));
    super.dispose();
  }

  ImageProvider _vaultThumbProvider(String filePath) {
    return FileImage(File(filePath));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.resumed) {
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, _hasChanged);
  }

  Future<void> _loadVault() async {
    final items = await vaultService.loadVaultItems();
    final settings = await vaultService.loadSettings();
    if (!mounted) return;
    setState(() {
      _items = items;
      _biometricEnabled = settings.biometricEnabled;
      _biometricAvailable = settings.biometricAvailable;
      _isLoading = false;
    });
  }

  Future<void> _restoreItem(VaultItem item) async {
    try {
      await vaultService.restoreVaultItem(item);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _hasChanged = true;
      });
      await _loadVault();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Restored successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Restore failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _deleteItem(VaultItem item) async {
    await vaultService.deleteVaultItem(item);
    if (!mounted) return;
    setState(() {
      _hasChanged = true;
    });
    await _loadVault();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Deleted permanently'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
      _isSelectionMode = _selectedItemIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _showSelectionActions() async {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleItems = _selectedTab == 0 ? _photos : _videos;
    final selectedItems = visibleItems
        .where((item) => _selectedItemIds.contains(item.fileName))
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          blurSigma: 18,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${_selectedItemIds.length} selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            for (final item in selectedItems) {
                              await _restoreItem(item);
                            }
                            _clearSelection();
                          },
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Restore All'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            for (final item in selectedItems) {
                              await _deleteItem(item);
                            }
                            _clearSelection();
                          },
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Delete All'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _clearSelection();
                      },
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showItemActions(VaultItem item) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          blurSigma: 18,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    path.basename(item.fileName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _restoreItem(item);
                          },
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Restore'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _deleteItem(item);
                          },
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSettingsSheet() async {
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return GlassContainer(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(34),
              ),
              blurSigma: 18,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ListTile(
                        leading: const Icon(Icons.pin_rounded),
                        title: const Text('Change PIN'),
                        subtitle: const Text('Set a new 4-digit PIN'),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _showPinChangeDialog();
                        },
                      ),
                      SwitchListTile(
                        value: _biometricEnabled,
                        onChanged: _biometricAvailable
                            ? (value) async {
                                await vaultService.setBiometricEnabled(value);
                                if (!mounted) return;
                                setState(() {
                                  _biometricEnabled = value;
                                });
                                setSheetState(() {
                                  _biometricEnabled = value;
                                });
                              }
                            : null,
                        title: const Text('Use fingerprint / biometrics'),
                        subtitle: Text(
                          _biometricAvailable
                              ? 'Unlock the vault faster'
                              : 'Biometric authentication is not available',
                        ),
                        secondary: const Icon(Icons.fingerprint_rounded),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.restart_alt_rounded,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          'Reset vault',
                          style: TextStyle(color: colorScheme.error),
                        ),
                        subtitle: const Text(
                          'Delete all vault content and clear the PIN',
                        ),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _confirmResetVault();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPinChangeDialog() async {
    String first = '';
    String second = '';
    final success = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Change PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'New 4-digit PIN'),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                onChanged: (value) => first = value,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                onChanged: (value) => second = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (success != true || first.length != 4 || first != second) {
      if (!mounted || success != true) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('PIN update failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    await vaultService.changePin(first);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('PIN updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _confirmResetVault() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset vault?'),
          content: const Text(
            'This deletes every file inside the Safe Folder and removes the PIN.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) return;
    await vaultService.resetVault();
    if (!mounted) return;
    setState(() {
      _hasChanged = true;
    });
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = settings.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final topBarColor = isDark
        ? const Color(0xFF0A0A0A)
        : const Color(0xFFFBFBFB);
    final visibleItems = _selectedTab == 0 ? _photos : _videos;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _isSelectionMode
            ? Text('${_selectedItemIds.length} selected')
            : const Text('Safe Folder'),
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
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: topBarColor),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: [
          if (_isSelectionMode)
            IconButton(
              tooltip: 'Actions',
              onPressed: _showSelectionActions,
              icon: const Icon(Icons.more_vert_rounded),
            )
          else
            IconButton(
              tooltip: 'Settings',
              onPressed: _showSettingsSheet,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        Color(0xFF050505),
                        Color(0xFF080808),
                        Color(0xFF0C0C0C),
                      ]
                    : const [
                        Color(0xFFFFFFFF),
                        Color(0xFFF9F9F9),
                        Color(0xFFF0F0F0),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity! > 0) {
                  // Swiped right - go to previous tab
                  if (_selectedTab > 0 && !_isSelectionMode) {
                    setState(() => _selectedTab = 0);
                  }
                } else if (details.primaryVelocity! < 0) {
                  // Swiped left - go to next tab
                  if (_selectedTab < 1 && !_isSelectionMode) {
                    setState(() => _selectedTab = 1);
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                child: Column(
                  children: [
                    GlassContainer(
                      borderRadius: BorderRadius.circular(28),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _VaultTabButton(
                                label: 'Photos',
                                isSelected: _selectedTab == 0,
                                onTap: () => setState(() => _selectedTab = 0),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _VaultTabButton(
                                label: 'Videos',
                                isSelected: _selectedTab == 1,
                                onTap: () => setState(() => _selectedTab = 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(30),
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : visibleItems.isEmpty
                            ? Center(
                                child: Text(
                                  _selectedTab == 0
                                      ? 'No private photos yet'
                                      : 'No private videos yet',
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(10),
                                physics: const BouncingScrollPhysics(),
                                itemCount: visibleItems.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 6,
                                      crossAxisSpacing: 6,
                                    ),
                                itemBuilder: (context, index) {
                                  final item = visibleItems[index];
                                  final isSelected =
                                      _selectedItemIds.contains(item.fileName);

                                  return GestureDetector(
                                    onTap: () {
                                      if (_isSelectionMode) {
                                        _toggleItemSelection(item.fileName);
                                      } else {
                                        Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                VaultPreviewScreen(
                                                  item: item,
                                                  allItems: visibleItems,
                                                  initialIndex: index,
                                                ),
                                          ),
                                        );
                                      }
                                    },
                                    onLongPress: () {
                                      _toggleItemSelection(item.fileName);
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          item.mediaType == VaultMediaType.photo
                                              ? Image(
                                                  image: _vaultThumbProvider(
                                                    item.vaultPath,
                                                  ),
                                                  fit: BoxFit.cover,
                                                )
                                              : Container(
                                                  color: Colors.black,
                                                  child: const Icon(
                                                    Icons.videocam_rounded,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                                ),
                                          Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withValues(
                                                      alpha: 0.66,
                                                    ),
                                                  ],
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      path.basename(
                                                        item.fileName,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: colorScheme.primary
                                                    .withValues(alpha: 0.4),
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        colorScheme.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.check,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultTabButton extends StatelessWidget {
  const _VaultTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.22)
                : Colors.transparent,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VaultPreviewScreen extends ConsumerStatefulWidget {
  const VaultPreviewScreen({
    super.key,
    required this.item,
    required this.allItems,
    required this.initialIndex,
  });

  final VaultItem item;
  final List<VaultItem> allItems;
  final int initialIndex;

  @override
  ConsumerState<VaultPreviewScreen> createState() => _VaultPreviewScreenState();
}

class _VaultPreviewScreenState extends ConsumerState<VaultPreviewScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  late PageController _pageController;
  late int currentIndex;
  final ValueNotifier<double> verticalDragNotifier = ValueNotifier<double>(0);

  double get dismissProgress =>
      (verticalDragNotifier.value / 200).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    if (widget.item.mediaType == VaultMediaType.video) {
      unawaited(_initializeVideo());
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _pageController.dispose();
    verticalDragNotifier.dispose();
    super.dispose();
  }

  ImageProvider _previewProvider(String filePath) {
    return FileImage(File(filePath));
  }

  Future<void> _initializeVideo({String? videoPath}) async {
    final path = videoPath ?? widget.item.vaultPath;
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    final chewie = ChewieController(
      videoPlayerController: controller,
      autoPlay: true,
      looping: false,
    );
    if (!mounted) {
      chewie.dispose();
      controller.dispose();
      return;
    }
    setState(() {
      _videoController = controller;
      _chewieController = chewie;
    });
  }

  Future<void> _updateVideoOnPageChange(int newIndex) async {
    // Dispose old video completely
    _chewieController?.dispose();
    _videoController?.dispose();
    _videoController = null;
    _chewieController = null;

    // Force rebuild to show loading indicator
    if (mounted) {
      setState(() {});
    }

    final newItem = widget.allItems[newIndex];
    if (newItem.mediaType == VaultMediaType.video) {
      await _initializeVideo(videoPath: newItem.vaultPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(settingsProvider).isDark(context);

    return ValueListenableBuilder<double>(
      valueListenable: verticalDragNotifier,
      builder: (context, verticalDrag, _) {
        final dismissProgress =
            (verticalDrag / 200).clamp(0.0, 1.0);

        return Scaffold(
          backgroundColor: Colors.black.withOpacity(
            (1.0 - dismissProgress).clamp(0.0, 1.0),
          ),
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              path.basename(widget.allItems[currentIndex].fileName),
            ),
            systemOverlayStyle: isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),
          body: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.delta.dy > 0) {
                verticalDragNotifier.value += details.delta.dy;
              }
            },
            onVerticalDragEnd: (details) {
              if (dismissProgress > 0.25 || details.velocity.pixelsPerSecond.dy > 500) {
                Navigator.pop(context);
              } else {
                verticalDragNotifier.value = 0;
              }
            },
            child: Transform.translate(
              offset: Offset(0, verticalDragNotifier.value),
              child: PageView.builder(
                controller: _pageController,
                physics: const FastPageScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                onPageChanged: (newIndex) async {
                  setState(() {
                    currentIndex = newIndex;
                  });
                  await _updateVideoOnPageChange(newIndex);
                },
                itemCount: widget.allItems.length,
                itemBuilder: (context, index) {
                  final item = widget.allItems[index];
                  return Center(
                    child: item.mediaType == VaultMediaType.photo
                        ? InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Image(
                              image: _previewProvider(item.vaultPath),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          )
                        : index == currentIndex && _chewieController != null
                            ? Chewie(controller: _chewieController!)
                            : const Center(
                                child: CircularProgressIndicator(),
                              ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
