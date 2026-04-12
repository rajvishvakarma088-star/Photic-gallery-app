import re

with open('lib/gallery_screen.dart', 'r') as f:
    text = f.read()

# 1. Update _thumbnailProviderFor to use strict LRU tracking
orig_pattern = r'''  ImageProvider<Object> _thumbnailProviderFor\(AssetEntity asset, int thumbPx\) \{
    if \(_thumbDiskCache\.isReady\) \{
      final cachedFile = _thumbDiskCache\.cachedFileSync\(asset\.id, thumbPx\);
      if \(cachedFile != null\) \{
        return FileImage\(cachedFile\);
      \}
    \}
    return AssetEntityImageProvider\(
      asset,
      isOriginal: false,
      thumbnailSize: ThumbnailSize\.square\(thumbPx\),
      thumbnailFormat: ThumbnailFormat\.jpeg,
    \);
  \}'''

replacement = r'''  ImageProvider<Object> _thumbnailProviderFor(AssetEntity asset, int thumbPx) {
    if (_thumbDiskCache.isReady) {
      final cachedFile = _thumbDiskCache.cachedFileSync(asset.id, thumbPx);
      if (cachedFile != null) return FileImage(cachedFile);
    }
    return AssetEntityImageProvider(
      asset,
      isOriginal: false,
      thumbnailSize: ThumbnailSize.square(thumbPx),
      thumbnailFormat: ThumbnailFormat.jpeg,
    );
  }'''

# Replace it securely? Actually, in gallery_screen.dart, wait, do they even maintain a _thumbCache?
