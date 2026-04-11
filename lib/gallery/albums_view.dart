import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../glass_container.dart';
import '../services/gallery_service.dart';
import 'gallery_album_widgets.dart' as gallery_album_widgets;
import 'premium_refresh_control.dart';

class AlbumsView extends StatelessWidget {
  final bool isLoadingAlbums;
  final List<AlbumSummary> albums;
  final ScrollController albumsScrollController;
  final ColorScheme colorScheme;
  final bool isDark;
  final Widget Function(AssetEntity asset, {int thumbPx}) buildImage;
  final Future<void> Function(AlbumSummary album) onAlbumTap;
  final Future<void> Function()? onRefresh;

  const AlbumsView({
    super.key,
    required this.isLoadingAlbums,
    required this.albums,
    required this.albumsScrollController,
    required this.colorScheme,
    required this.isDark,
    required this.buildImage,
    required this.onAlbumTap,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoadingAlbums) {
      return const Center(child: CircularProgressIndicator());
    }

    if (albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found',
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final featuredAlbums = albums
        .where((album) => album.isFeatured)
        .toList(growable: false);
    final otherAlbums = albums
        .where((album) => !album.isFeatured)
        .toList(growable: false);

    return RawScrollbar(
      controller: albumsScrollController,
      interactive: true,
      thickness: 6.0,
      radius: const Radius.circular(8),
      thumbVisibility: false,
      thumbColor: colorScheme.onSurface.withValues(alpha: 0.4),
      child: CustomScrollView(
        controller: albumsScrollController,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.normal)),
        cacheExtent: 1400,
        slivers: [
          if (onRefresh != null)
            PremiumRefreshControl(
              onRefresh: onRefresh!,
              topPadding: MediaQuery.of(context).padding.top + kToolbarHeight,
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight + 10, 16, 8),
            child: RepaintBoundary(
              child: GlassContainer(
                padding: const EdgeInsets.all(18),
                borderRadius: BorderRadius.circular(32),
                enableBlur: false,
                blurSigma: 0,
                backgroundColor: isDark
                    ? const Color(0xFF1A102D).withValues(alpha: 0.9)
                    : const Color(0xFFF7F1FF).withValues(alpha: 0.94),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Albums',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Browse photos by folder with rich previews and quick counts.',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.72),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        gallery_album_widgets.buildGalleryStatsChip(
                          icon: Icons.folder_open_rounded,
                          label: '${albums.length} folders',
                          color: colorScheme.primaryContainer.withOpacity(0.9),
                          textColor: colorScheme.onPrimaryContainer,
                        ),
                        gallery_album_widgets.buildGalleryStatsChip(
                          icon: Icons.photo_library_rounded,
                          label:
                              '${albums.fold<int>(0, (sum, album) => sum + album.count)} photos',
                          color: colorScheme.secondaryContainer.withOpacity(
                            0.9,
                          ),
                          textColor: colorScheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (featuredAlbums.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Highlights',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${featuredAlbums.length} picked',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (featuredAlbums.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                cacheExtent: 1000,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  decelerationRate: ScrollDecelerationRate.fast,
                ),
                itemCount: featuredAlbums.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final album = featuredAlbums[index];
                  return RepaintBoundary(
                    child: gallery_album_widgets.buildFeaturedAlbumCard(
                      album: album,
                      colorScheme: colorScheme,
                      isDark: isDark,
                      buildImage: buildImage,
                      onTap: () => onAlbumTap(album),
                    ),
                  );
                },
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
            child: Text(
              featuredAlbums.isEmpty ? 'All Albums' : 'More Albums',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          sliver: SliverFixedExtentList(
            itemExtent: 110,
            delegate: SliverChildBuilderDelegate((context, index) {
              final album = otherAlbums[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: gallery_album_widgets.buildAlbumListTile(
                  album: album,
                  colorScheme: colorScheme,
                  buildImage: buildImage,
                  onTap: () => onAlbumTap(album),
                ),
              );
            }, childCount: otherAlbums.length),
          ),
        ),
      ],
     ),
    );
  }
}
