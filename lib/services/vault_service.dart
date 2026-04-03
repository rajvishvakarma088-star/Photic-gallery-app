import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_database.dart';

class VaultSettings {
  const VaultSettings({
    required this.hasPin,
    required this.biometricEnabled,
    required this.biometricAvailable,
    required this.isUnlocked,
  });

  final bool hasPin;
  final bool biometricEnabled;
  final bool biometricAvailable;
  final bool isUnlocked;
}

class VaultService {
  VaultService._();

  static final VaultService instance = VaultService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _pinKey = 'vault_pin';
  static const String _biometricEnabledKey = 'vault_biometric_enabled';
  static const String _vaultPhotosDir = 'vault/photos';
  static const String _vaultVideosDir = 'vault/videos';

  final VaultDatabase database = VaultDatabase.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isUnlocked = false;

  bool get isUnlocked => _isUnlocked;

  Future<VaultSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricAvailable = await canUseBiometrics();
    return VaultSettings(
      hasPin: await hasPin(),
      biometricEnabled: prefs.getBool(_biometricEnabledKey) ?? false,
      biometricAvailable: biometricAvailable,
      isUnlocked: _isUnlocked,
    );
  }

  Future<bool> hasPin() async {
    final pin = await _secureStorage.read(key: _pinKey);
    return pin != null && pin.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    await _secureStorage.write(key: _pinKey, value: _encodePin(pin));
    _isUnlocked = false;
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _secureStorage.read(key: _pinKey);
    final matches = stored != null && stored == _encodePin(pin);
    if (matches) {
      _isUnlocked = true;
    }
    return matches;
  }

  Future<void> changePin(String pin) async {
    await setPin(pin);
  }

  Future<void> lock() async {
    _isUnlocked = false;
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Unlock your Safe Folder',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
        ),
      );
      if (didAuth) {
        _isUnlocked = true;
      }
      return didAuth;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  Future<List<VaultItem>> loadVaultItems() async {
    final items = await database.loadItems();
    final staleItems = items
        .where((item) => !item.exists)
        .toList(growable: false);
    for (final item in staleItems) {
      if (item.id != null) {
        await database.removeItem(item.id!);
      }
    }
    return items.where((item) => item.exists).toList(growable: false);
  }

  Future<VaultItem> moveAssetToVault(AssetEntity asset) async {
    final sourceFile = await asset.file;
    if (sourceFile == null || !await sourceFile.exists()) {
      throw Exception('Original file is not available');
    }

    final targetDirectory = await _vaultDirectoryFor(asset.type);
    await targetDirectory.create(recursive: true);

    final originalPath = sourceFile.path;
    final extension = path.extension(originalPath);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${asset.id}$extension';
    final targetPath = path.join(targetDirectory.path, fileName);
    final copiedFile = await sourceFile.copy(targetPath);

    final item = await database.addItem(
      VaultItem(
        id: null,
        fileName: path.basename(originalPath),
        vaultPath: copiedFile.path,
        originalPath: originalPath,
        originalRelativePath: _relativeGalleryPathFromAbsolute(originalPath),
        mediaType: asset.type == AssetType.video
            ? VaultMediaType.video
            : VaultMediaType.photo,
        createdAt: DateTime.now(),
      ),
    );

    await PhotoManager.editor.deleteWithIds([asset.id]);
    return item;
  }

  Future<void> deleteVaultItem(VaultItem item) async {
    final file = File(item.vaultPath);
    if (await file.exists()) {
      await file.delete();
    }
    if (item.id != null) {
      await database.removeItem(item.id!);
    }
  }

  Future<AssetEntity> restoreVaultItem(VaultItem item) async {
    final file = File(item.vaultPath);
    if (!await file.exists()) {
      throw Exception('Vault file is missing');
    }

    final relativePath = item.originalRelativePath.isEmpty
        ? _defaultRelativePathFor(item.mediaType)
        : item.originalRelativePath;

    final AssetEntity restoredAsset;
    if (item.mediaType == VaultMediaType.photo) {
      restoredAsset = await PhotoManager.editor.saveImageWithPath(
        file.path,
        title: item.fileName,
        relativePath: relativePath,
      );
    } else {
      restoredAsset = await PhotoManager.editor.saveVideo(
        file,
        title: item.fileName,
        relativePath: relativePath,
      );
    }

    await deleteVaultItem(item);
    return restoredAsset;
  }

  Future<void> resetVault() async {
    final items = await database.loadItems();
    for (final item in items) {
      final file = File(item.vaultPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await database.clear();
    await _secureStorage.delete(key: _pinKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricEnabledKey);
    _isUnlocked = false;
  }

  Future<Directory> _vaultDirectoryFor(AssetType assetType) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final folderName = assetType == AssetType.video
        ? _vaultVideosDir
        : _vaultPhotosDir;
    return Directory(path.join(documentsDirectory.path, folderName));
  }

  String _encodePin(String pin) {
    return base64Encode(utf8.encode(pin));
  }

  String _relativeGalleryPathFromAbsolute(String absolutePath) {
    if (absolutePath.isEmpty) return '';
    final normalized = path.normalize(absolutePath);
    final segments = path.split(normalized);
    final storageIndex = segments.lastIndexOf('0');
    if (storageIndex >= 0 && storageIndex + 1 < segments.length - 1) {
      return segments.sublist(storageIndex + 1, segments.length - 1).join('/');
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return _defaultRelativePathFor(VaultMediaType.photo);
    }

    return '';
  }

  String _defaultRelativePathFor(VaultMediaType type) {
    return type == VaultMediaType.video
        ? 'Movies/Restored'
        : 'Pictures/Restored';
  }
}
