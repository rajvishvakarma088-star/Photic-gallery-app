import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'music_service.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  
  late AudioPlayer _audioPlayer;
  MusicFile? _currentMusic;
  List<MusicFile> _playlist = [];
  int _currentIndex = 0;
  
  bool _isPlaying = false;
  bool _isInitialized = false;
  
  final ValueNotifier<MusicFile?> currentMusicNotifier = ValueNotifier<MusicFile?>(null);
  final ValueNotifier<bool> isMiniPlayerVisible = ValueNotifier<bool>(true);

  factory AudioPlayerService() {
    return _instance;
  }

  AudioPlayerService._internal() {
    _initializeAudioPlayer();
  }

  void _initializeAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _isInitialized = true;
  }

  AudioPlayer get audioPlayer => _audioPlayer;
  
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  
  MusicFile? get currentMusic => _currentMusic;
  int get currentIndex => _currentIndex;
  List<MusicFile> get playlist => _playlist;
  
  Duration get position => _audioPlayer.position;
  Duration get duration => _audioPlayer.duration ?? Duration.zero;
  
  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;

  Future<void> setPlaylist(List<MusicFile> musics, {int startIndex = 0}) async {
    _playlist = musics;
    if (_playlist.isNotEmpty) {
      _currentIndex = startIndex.clamp(0, _playlist.length - 1);
      await playMusic(_playlist[_currentIndex]);
    }
  }

  Future<void> playMusic(MusicFile music) async {
    try {
      _currentMusic = music;
      currentMusicNotifier.value = music;
      isMiniPlayerVisible.value = true;
      await _audioPlayer.setFilePath(music.path);
      await _audioPlayer.play();
      _isPlaying = true;
    } catch (e) {
      print('Error playing music: $e');
      _isPlaying = false;
    }
  }

  Future<void> play() async {
    if (_currentMusic != null) {
      try {
        isMiniPlayerVisible.value = true;
        await _audioPlayer.play();
        _isPlaying = true;
      } catch (e) {
        print('Error playing: $e');
      }
    }
  }

  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _isPlaying = false;
    } catch (e) {
      print('Error pausing: $e');
    }
  }

  Future<void> resume() async {
    try {
      isMiniPlayerVisible.value = true;
      await _audioPlayer.play();
      _isPlaying = true;
    } catch (e) {
      print('Error resuming: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
    } catch (e) {
      print('Error stopping: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      print('Error seeking: $e');
    }
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    
    _currentIndex = (_currentIndex + 1) % _playlist.length;
    await playMusic(_playlist[_currentIndex]);
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) return;
    
    _currentIndex = (_currentIndex - 1).isNegative ? _playlist.length - 1 : _currentIndex - 1;
    await playMusic(_playlist[_currentIndex]);
  }

  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
    } catch (e) {
      print('Error disposing audio player: $e');
    }
  }
}
