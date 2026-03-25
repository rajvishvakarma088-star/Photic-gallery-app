import 'package:photo_manager/photo_manager.dart';

class GalleryService {
  Future<List<AssetEntity>> fetchImages(int page) async {
    final permission = await PhotoManager.requestPermissionExtend();

    if (!permission.isAuth) return [];

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (albums.isEmpty) return [];

    final recentAlbum = albums.first;

    return recentAlbum.getAssetListPaged(
      page: page,
      size: 100,
    );
  }
}
