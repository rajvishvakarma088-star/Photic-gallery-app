🎵 Music Player - Troubleshooting & Fix Guide

## Issues Fixed

✅ **Android Permissions**
- Added READ_MEDIA_AUDIO permission for music file access
- Added MANAGE_AUDIO permission for playback control
- Updated AndroidManifest.xml

✅ **Music File Discovery**
- Improved directory scanning in MusicService
- Added error handling for inaccessible directories
- Filters out corrupted/small files (< 100KB)
- Scans multiple common paths:
  - /storage/emulated/0/Music
  - /storage/emulated/0/Download
  - /storage/emulated/0/Documents
  - /storage/emulated/0/DCIM

✅ **Index Tab Update**
- Fixed recyclebin tab detection (was 4, now 5)
- Music tab correctly at index 4

## How to Test

1. **Clean rebuild:**
```bash
flutter clean
flutter pub get
flutter run
```

2. **Grant permissions when prompted:**
   - Storage access ✓
   - Audio access ✓

3. **Add test music files:**
   - Copy .mp3, .wav, or .m4a files to your device's Music folder
   - Or Download folder for testing

4. **Check the Music tab:**
   - Tap the Music icon at bottom
   - Should see list of discovered songs
   - Tap a song to open full player

## Debugging Tips

Check the console for:
```
I/flutter: Loaded X music files
```

If you see "Loaded 0 music files":
- Verify music files exist on device
- Check file sizes (must be > 100KB)
- Ensure proper file extensions: .mp3, .wav, .m4a, .aac, .ogg, .flac

## Common Issues

**Audio Format Warnings**
- "Unknown native audio format" warnings are normal
- just_audio automatically uses supported codecs
- Not an error, just system logging

**Music Not Visible**
1. Verify permissions granted in Settings
2. Add music files to common directories
3. Restart app after adding files
4. Check console logs for file count

**Files Not Showing in List**
- Files must be > 100KB
- Only MP3, WAV, M4A, AAC, OGG, FLAC supported
- Files in subdirectories are found recursively

## Next Steps

If music still not appearing:
1. Check Android version (Android 6.0+ required)
2. Verify storage permissions in system settings
3. Try adding files to Download folder first
4. Restart device if needed

---

**Status**: All fixes applied and ready to test 🚀
Date: April 4, 2026
