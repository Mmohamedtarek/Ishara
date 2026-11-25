# Read by the Flutter Gradle plugin for release builds (R8).

# Moonshine (DECISIONS TV-21): the JNI entry points, and the classes the native
# code looks up by name (libmoonshine-jni.so: FindClass, fields, constructors).
-keep class ai.moonshine.voice.JNI { *; }
-keep class ai.moonshine.voice.Transcript { *; }
-keep class ai.moonshine.voice.TranscriptLine { *; }
-keep class ai.moonshine.voice.WordTiming { *; }
-keep class ai.moonshine.voice.SpeakerSpan { *; }
-keep class ai.moonshine.voice.TranscriberOption { *; }
-keep class ai.moonshine.voice.SpeechClip { *; }
-keep class ai.moonshine.voice.TtsChunk { *; }
-keep class ai.moonshine.voice.TtsSynthesisResult { *; }

# Moonshine's downloader (AssetDownloader, MoonshineDownloadWorker) and its
# permission helper use OkHttp, WorkManager and androidx.core, left out on
# purpose (isTransitive = false). Nothing above reaches them, so R8 removes
# them; these lines only silence the missing-class warnings.
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn androidx.work.**
