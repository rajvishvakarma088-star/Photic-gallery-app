import 'package:photo_manager/photo_manager.dart';

class GalleryService {
  Future<List<AssetEntity>> fetchImages({
    int page = 0,
    int size = 120,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();

    if (!permission.isAuth) return [];

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (albums.isEmpty) return [];

    // The first album is typically the device-wide "Recent/All Photos" source
    // and is much faster than merging every individual album.
    final primaryAlbum = albums.first;
    final images = await primaryAlbum.getAssetListPaged(
      page: page,
      size: size,
    );

    images.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    return images;
  }
}
