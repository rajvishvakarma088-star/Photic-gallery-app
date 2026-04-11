import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass_container.dart';
import 'services/screenshot_protection_service.dart';
import 'services/vault_service.dart';
import 'providers/settings_provider.dart';
import 'vault_screen.dart';

enum _VaultPinStage { create, confirm, unlock }

class VaultLockScreen extends ConsumerStatefulWidget {
  const VaultLockScreen({super.key});

  @override
  ConsumerState<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends ConsumerState<VaultLockScreen>
    with SingleTickerProviderStateMixin {
  final VaultService vaultService = VaultService.instance;
  late final AnimationController _shakeController;
  String _enteredPin = '';
  String _firstPin = '';
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  _VaultPinStage _stage = _VaultPinStage.unlock;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    unawaited(ScreenshotProtectionService.setProtected(false));
    super.dispose();
  }

  Future<void> _initialize() async {
    await ScreenshotProtectionService.setProtected(true);
    final settings = await vaultService.loadSettings();
    if (!mounted) return;

    setState(() {
      _biometricAvailable = settings.biometricAvailable;
      _biometricEnabled = settings.biometricEnabled;
      _stage = settings.hasPin ? _VaultPinStage.unlock : _VaultPinStage.create;
      _isLoading = false;
    });

    if (settings.hasPin &&
        settings.biometricAvailable &&
        settings.biometricEnabled) {
      await _tryBiometricUnlock();
    }
  }

  Future<void> _tryBiometricUnlock() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final unlocked = await vaultService.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (unlocked) {
      await _openVault();
    }
  }

  Future<void> _handleDigit(String digit) async {
    if (_isProcessing || _enteredPin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin += digit;
    });

    if (_enteredPin.length == 4) {
      await _submitPin();
    }
  }

  void _deleteDigit() {
    if (_isProcessing || _enteredPin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _submitPin() async {
    if (_enteredPin.length != 4) return;
    setState(() => _isProcessing = true);

    if (_stage == _VaultPinStage.create) {
      final firstPin = _enteredPin;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      setState(() {
        _firstPin = firstPin;
        _enteredPin = '';
        _stage = _VaultPinStage.confirm;
        _isProcessing = false;
      });
      return;
    }

    if (_stage == _VaultPinStage.confirm) {
      if (_enteredPin == _firstPin) {
        await vaultService.setPin(_enteredPin);
        await vaultService.verifyPin(_enteredPin);
        if (!mounted) return;
        setState(() {
          _enteredPin = '';
          _isProcessing = false;
        });
        await _openVault();
        return;
      }

      await _handleInvalidPin('PINs do not match');
      return;
    }

    final success = await vaultService.verifyPin(_enteredPin);
    if (success) {
      if (!mounted) return;
      setState(() {
        _enteredPin = '';
        _isProcessing = false;
      });
      await _openVault();
      return;
    }

    await _handleInvalidPin('Wrong PIN');
  }

  Future<void> _handleInvalidPin(String message) async {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _shakeController
      ..reset()
      ..forward();
    setState(() {
      _enteredPin = '';
      _isProcessing = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openVault() async {
    final changed = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: const VaultScreen(),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, changed ?? false);
  }

  String get _title {
    switch (_stage) {
      case _VaultPinStage.create:
        return 'Set a 4-digit PIN';
      case _VaultPinStage.confirm:
        return 'Confirm your PIN';
      case _VaultPinStage.unlock:
        return 'Unlock Safe Folder';
    }
  }

  String get _subtitle {
    switch (_stage) {
      case _VaultPinStage.create:
        return 'Create your vault key for private photos and videos.';
      case _VaultPinStage.confirm:
        return 'Enter the same PIN once more to finish setup.';
      case _VaultPinStage.unlock:
        return 'Enter your PIN or use biometrics to access the vault.';
    }
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
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Safe Folder'),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: settings.getBackgroundGradient(isDark),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(34),
                  blurSigma: 18,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                    child: _isLoading
                        ? const SizedBox(
                            height: 320,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_moon_rounded,
                                color: colorScheme.primary,
                                size: 46,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.72,
                                  ),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 22),
                              AnimatedBuilder(
                                animation: _shakeController,
                                builder: (context, child) {
                                  final progress = _shakeController.value;
                                  final offset =
                                      (0.5 - (progress % 0.5)).abs() * 28 - 7;
                                  return Transform.translate(
                                    offset: Offset(
                                      progress == 0 ? 0 : offset,
                                      0,
                                    ),
                                    child: child,
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(4, (index) {
                                    final filled = index < _enteredPin.length;
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: filled
                                            ? colorScheme.primary
                                            : colorScheme.onSurface.withValues(
                                                alpha: 0.16,
                                              ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _PinPad(
                                onDigit: _handleDigit,
                                onDelete: _deleteDigit,
                                showBiometric:
                                    _stage == _VaultPinStage.unlock &&
                                    _biometricAvailable,
                                onBiometric: _biometricEnabled
                                    ? _tryBiometricUnlock
                                    : null,
                                isProcessing: _isProcessing,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.onDigit,
    required this.onDelete,
    required this.showBiometric,
    required this.onBiometric,
    required this.isProcessing,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool showBiometric;
  final VoidCallback? onBiometric;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final digits = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '',
      '0',
      'delete',
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount: digits.length,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        final value = digits[index];
        if (value.isEmpty) {
          return _PinButton(
            label: '',
            icon: showBiometric ? Icons.fingerprint_rounded : null,
            enabled: showBiometric && onBiometric != null && !isProcessing,
            onTap: showBiometric && onBiometric != null ? onBiometric! : null,
          );
        }
        if (value == 'delete') {
          return _PinButton(
            label: '',
            icon: Icons.backspace_outlined,
            enabled: !isProcessing,
            onTap: onDelete,
          );
        }
        return _PinButton(
          label: value,
          enabled: !isProcessing,
          onTap: () => onDigit(value),
        );
      },
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({
    required this.label,
    required this.enabled,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool enabled;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: enabled ? onTap : null,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, color: colorScheme.onSurface, size: 28)
                : Text(
                    label,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
