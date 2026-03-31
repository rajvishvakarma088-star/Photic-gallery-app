import 'package:photo_manager/photo_manager.dart';

class GallerySection {
  const GallerySection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<AssetEntity> items;
}
