import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final permission = await PhotoManager.requestPermissionExtend();
  print('Permission: \$permission');
  final albums = await PhotoManager.getAssetPathList(type: RequestType.audio, hasAll: true);
  print('Albums: \${albums.length}');
  if (albums.isNotEmpty) {
    final allAudio = albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
    final count = await allAudio.assetCountAsync;
    print('Audio count: \$count');
    final assets = await allAudio.getAssetListPaged(page: 0, size: 5);
    for (var asset in assets) {
      print('Asset title: \${asset.title}, type: \${asset.type}');
      final file = await asset.file;
      print('Path: \${file?.path}');
    }
  }
}
