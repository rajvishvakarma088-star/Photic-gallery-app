import 'package:photo_manager/photo_manager.dart';

import 'gallery_section.dart';

List<GallerySection> buildGallerySections(
  List<AssetEntity> items,
  DateTime Function(AssetEntity asset) resolveAssetDate,
) {
  if (items.isEmpty) return const [];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  const monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final sections = <GallerySection>[];
  String? currentTitle;
  List<AssetEntity> currentItems = [];

  String titleFor(AssetEntity asset) {
    final date = resolveAssetDate(asset);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return '${monthNames[date.month - 1]} ${date.year}';
  }

  for (final asset in items) {
    final title = titleFor(asset);
    if (currentTitle != title) {
      if (currentTitle != null) {
        sections.add(GallerySection(title: currentTitle, items: currentItems));
      }
      currentTitle = title;
      currentItems = [asset];
    } else {
      currentItems.add(asset);
    }
  }

  if (currentTitle != null) {
    sections.add(GallerySection(title: currentTitle, items: currentItems));
  }

  return sections;
}
