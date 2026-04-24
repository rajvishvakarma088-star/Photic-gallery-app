import 'dart:async';

import 'package:flutter/services.dart';

import 'gallery_service.dart';

enum GalleryChangeKind {
  fileCreated,
  mediaStoreChange,
}

class GalleryChangeEvent {
  const GalleryChangeEvent({
    required this.kind,
    required this.timestamp,
    this.path,
    this.uri,
  });

  final GalleryChangeKind kind;
  final String? path;
  final String? uri;
  final DateTime timestamp;

  factory GalleryChangeEvent.fromMap(Map<dynamic, dynamic> map) {
    final kindValue = map['kind']?.toString();
    final kind = kindValue == 'file_created'
        ? GalleryChangeKind.fileCreated
        : GalleryChangeKind.mediaStoreChange;

    return GalleryChangeEvent(
      kind: kind,
      path: map['path']?.toString(),
      uri: map['uri']?.toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class GalleryRepository extends GalleryService {
  GalleryRepository._();

  static final GalleryRepository instance = GalleryRepository._();

  static const EventChannel _mediaStoreChangeChannel = EventChannel(
    'com.example.pixora/media_store_changes',
  );

  final StreamController<GalleryChangeEvent> _changeController =
      StreamController<GalleryChangeEvent>.broadcast();
  StreamSubscription<dynamic>? _nativeSubscription;
  bool _watching = false;

  Stream<GalleryChangeEvent> get changes => _changeController.stream;

  Future<void> startWatching() async {
    if (_watching) return;
    _watching = true;
    _nativeSubscription = _mediaStoreChangeChannel
        .receiveBroadcastStream()
        .listen(_handleNativeEvent, onError: (_) {});
  }

  Future<void> stopWatching() async {
    _watching = false;
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
  }

  void _handleNativeEvent(dynamic event) {
    if (event is Map) {
      _changeController.add(GalleryChangeEvent.fromMap(event));
    }
  }
}
