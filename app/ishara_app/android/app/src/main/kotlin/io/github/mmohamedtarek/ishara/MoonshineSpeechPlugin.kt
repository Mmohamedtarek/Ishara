package io.github.mmohamedtarek.ishara

import android.Manifest
import android.annotation.SuppressLint
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.widget.Toast
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * English speech to text on the phone with Moonshine Small (DECISIONS TV-21).
 *
 * The model ships in the APK and is copied to the files folder on first use
 * ([MoonshineModelStore]). Moonshine itself is only touched through
 * [MoonshineEngine], and never below API 26. Audio stays in memory and is
 * never saved; nothing here uses the network. Under memory pressure the
 * model is freed when no listen is on, and loaded again on the next use.
 */
class MoonshineSpeechPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private class Session(val id: Int) {
        @Volatile var stop = false
        @Volatile var cancel = false
        @Volatile var micError: String? = null

        /** Moonshine got audio from this session. */
        @Volatile var fed = false
        val audio = LinkedBlockingQueue<FloatArray>()
    }

    private lateinit var context: Context
    private lateinit var store: MoonshineModelStore
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    /** Copies and loads the model and runs one session at a time. */
    private val engine = Executors.newSingleThreadExecutor { Thread(it, "moonshine-engine") }

    /** Only touched on [engine]. */
    private var model: MoonshineEngine? = null

    /** Why the model can't be used in this app run; only touched on [engine]. */
    private var unusable: Map<String, Any?>? = null

    /** When a prepare last answered "ready" (engine thread): a press starts next. */
    private var readyAt = 0L

    /** Only set on the main thread. */
    @Volatile private var active: Session? = null

    private val memory = object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) {
            @Suppress("DEPRECATION") // still sent below API 34
            val pressure = level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL
            if (pressure) freeWhenIdle("trim level $level")
        }

        override fun onConfigurationChanged(newConfig: Configuration) = Unit

        @Deprecated("Still sent on old phones")
        override fun onLowMemory() = freeWhenIdle("low memory")
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        store = MoonshineModelStore(context)
        context.registerComponentCallbacks(memory)
        methods = MethodChannel(binding.binaryMessenger, "ishara/moonshine").also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, "ishara/moonshine/events").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context.unregisterComponentCallbacks(memory)
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        sink = null
        cancelActive()
        engine.execute {
            model?.free()
            model = null
        }
        engine.shutdown()
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        cancelActive() // nobody is listening: never leave the mic open
    }

    private fun cancelActive() {
        active?.cancel = true
        active = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                // Never cancels a listen: a preload (Talk opened or resumed)
                // can arrive while one is on. A session left by a Dart hot
                // restart ends at the next "start".
                engine.execute {
                    val answer = safePrepare()
                    if (answer["status"] == "ready") readyAt = SystemClock.elapsedRealtime()
                    main.post { result.success(answer) }
                }
            }
            "start" -> {
                val session = Session(call.argument<Int>("session") ?: -1)
                cancelActive()
                active = session
                engine.execute { runSession(session) }
                result.success(null)
            }
            "stop" -> {
                active?.takeIf { it.id == call.argument<Int>("session") }?.stop = true
                result.success(null)
            }
            "cancel" -> {
                val session = active?.takeIf { it.id == call.argument<Int>("session") }
                session?.cancel = true
                if (session != null) active = null
                result.success(null)
            }
            "memory" -> Thread({
                val answer = memoryNow()
                main.post { result.success(answer) }
            }, "moonshine-memory").start()
            "debugNotice" -> {
                // Debug builds only: says English is not on Moonshine.
                if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                    Toast.makeText(context, call.argument<String>("text") ?: "", Toast.LENGTH_LONG)
                        .show()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun memoryNow(): Map<String, Any> = mapOf(
        "pssKb" to Debug.getPss(),
        "nativeHeapKb" to Debug.getNativeHeapAllocatedSize() / 1024,
    )

    /** [prepare], never throwing on the engine thread (that would end the app). */
    private fun safePrepare(): Map<String, Any?> = try {
        prepare()
    } catch (t: Throwable) {
        Log.e(TAG, "prepare failed", t)
        mapOf("status" to "failed", "message" to "prepare: ${t.javaClass.simpleName}")
    }

    /** On [engine]: copies (first use) and loads the model. */
    private fun prepare(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf("status" to "unsupported", "message" to "API ${Build.VERSION.SDK_INT}")
        }
        if (model != null) return mapOf("status" to "ready", "cached" to true)
        unusable?.let { return it }
        var copy = store.ensure()
        if (!copy.ready) return remember(copy.status, copy.fields)
        val pssBefore = Debug.getPss()
        val started = SystemClock.elapsedRealtime()
        var (loaded, error) = MoonshineEngine.load(store.dir)
        // A copy that won't load: copy it again once, then give up. Only when
        // the files may be damaged: a copy just made or just hash-checked (or
        // one that passes the check now) is fine, so the cause is elsewhere
        // (e.g. memory) and copying 142 MB again on every start can't help.
        if (loaded == null && copy.fields["copy"] == "kept" && !store.intact()) {
            Log.w(TAG, "model failed to load ($error) and is damaged, copying it again")
            store.delete()
            copy = store.ensure(copyAgain = true)
            if (!copy.ready) return remember(copy.status, copy.fields)
            val again = MoonshineEngine.load(store.dir)
            loaded = again.first
            error = again.second
        }
        if (loaded == null) return remember("failed", mapOf("message" to error))
        model = loaded
        val loadMs = SystemClock.elapsedRealtime() - started
        val pssAfter = Debug.getPss()
        Log.i(TAG, "model loaded in $loadMs ms (${copy.fields}), PSS $pssBefore -> $pssAfter kB")
        return mapOf(
            "status" to "ready",
            "cached" to false,
            "loadMs" to loadMs,
            "pssBeforeKb" to pssBefore,
            "pssAfterKb" to pssAfter,
            "nativeHeapKb" to Debug.getNativeHeapAllocatedSize() / 1024,
        ) + copy.fields
    }

    /** Not usable: kept for this app run, except "no space" (it may change). */
    private fun remember(status: String, fields: Map<String, Any?>): Map<String, Any?> {
        val answer = mapOf("status" to status) + fields
        Log.e(TAG, "model not usable: $answer")
        if (status != MoonshineModelStore.NO_SPACE) unusable = answer
        return answer
    }

    /** Frees the model under memory pressure, never during a listen. */
    private fun freeWhenIdle(why: String) {
        try {
            engine.execute {
                val loaded = model ?: return@execute
                if (active != null) {
                    Log.i(TAG, "model kept ($why): a listen is on")
                    return@execute
                }
                // A press was just told "ready": its start follows, and a
                // reload inside the listen would lose its first words.
                if (SystemClock.elapsedRealtime() - readyAt < PRESS_GRACE_MS) {
                    Log.i(TAG, "model kept ($why): a press is starting")
                    return@execute
                }
                loaded.free()
                model = null
                Log.i(TAG, "model freed ($why)")
            }
        } catch (e: RejectedExecutionException) {
            // detached
        }
    }

    @SuppressLint("MissingPermission") // checked just before
    private fun runSession(s: Session) {
        if (s.cancel) return
        // Freed under memory pressure since the prepare: load it again.
        val m = model ?: run {
            safePrepare()
            model
        } ?: return fail(s, "model_not_loaded")
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return fail(s, "permission")
        }
        var record: AudioRecord? = null
        var stream = -1
        var reader: Thread? = null
        try {
            val minBytes = AudioRecord.getMinBufferSize(RATE, CHANNEL, ENCODING)
            if (minBytes <= 0) return fail(s, "mic_unsupported")
            record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                RATE,
                CHANNEL,
                ENCODING,
                max(minBytes, RATE * 2 * 2), // 2 s, so a slow decode loses nothing
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) return fail(s, "mic_init")
            stream = m.startStream()
            if (stream < 0) return fail(s, "stream_start")
            val mic: AudioRecord = record
            val thread = Thread({ readMic(s, mic) }, "moonshine-mic")
            thread.start()
            reader = thread
            record = null // from here the reader thread owns and releases it
            if (!feed(s, m, stream)) {
                if (!s.cancel) fail(s, "decode")
                return
            }
            reader.join(READER_JOIN_MS)
            if (s.cancel) return
            s.micError?.let {
                // Words already captured are still decoded; the mic is closed.
                if (!s.fed) return fail(s, it)
                Log.w(TAG, "session ${s.id}: mic ended early ($it)")
            }

            val started = SystemClock.elapsedRealtime()
            val final = m.finish(stream) ?: return fail(s, "decode")
            val decodeMs = SystemClock.elapsedRealtime() - started
            emit(s, mapOf("type" to "final", "text" to final, "decodeMs" to decodeMs))
            main.post { if (active === s) active = null }
        } catch (e: Throwable) {
            Log.e(TAG, "session failed: ${e.javaClass.simpleName}")
            fail(s, "engine")
        } finally {
            s.stop = true // the reader ends and releases the mic, whatever happened
            record?.release()
            reader?.join(READER_JOIN_MS)
            if (stream >= 0) m.freeStream(stream)
        }
    }

    /** Feeds the mic to Moonshine until it ends; false if decoding failed. */
    private fun feed(s: Session, m: MoonshineEngine, stream: Int): Boolean {
        var sinceUpdate = 0
        var shown = ""
        while (true) {
            val first = s.audio.poll(POLL_MS, TimeUnit.MILLISECONDS) ?: continue
            if (first === END) return true
            if (s.cancel) continue // keep draining until the reader's END
            var chunk: FloatArray? = first
            while (chunk != null) {
                if (chunk === END) return true
                if (!m.addAudio(stream, chunk, RATE)) return false
                s.fed = true
                sinceUpdate += chunk.size
                chunk = s.audio.poll()
            }
            if (sinceUpdate >= UPDATE_SAMPLES && !s.cancel) {
                sinceUpdate = 0
                val text = m.text(stream) ?: return false
                if (text != shown) {
                    shown = text
                    emit(s, mapOf("type" to "partial", "text" to text))
                }
            }
        }
    }

    /** Owns [record]: always stops and releases it, then marks the end. */
    private fun readMic(s: Session, record: AudioRecord) {
        try {
            record.startRecording()
            if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                s.micError = "mic_start"
                return
            }
            val pcm = ShortArray(CHUNK)
            var filled = 0
            var live = false
            // Non-blocking: a stalled mic can never hold up stop or cancel.
            while (!s.stop && !s.cancel) {
                val n = record.read(pcm, filled, CHUNK - filled, AudioRecord.READ_NON_BLOCKING)
                if (n < 0) {
                    s.micError = "mic_read"
                    break
                }
                if (n == 0) {
                    Thread.sleep(READ_IDLE_MS)
                    continue
                }
                filled += n
                if (filled == CHUNK) {
                    live = pushAudio(s, pcm, filled, live)
                    filled = 0
                }
            }
            if (!s.cancel && filled > 0) pushAudio(s, pcm, filled, live)
        } catch (e: Exception) {
            Log.e(TAG, "mic failed: ${e.javaClass.simpleName}")
            s.micError = "mic_error"
        } finally {
            try {
                record.stop()
            } catch (_: IllegalStateException) {
                // never started
            }
            record.release()
            s.audio.put(END)
        }
    }

    /** Queues [n] samples; returns whether the mic is live (TV-19). */
    private fun pushAudio(s: Session, pcm: ShortArray, n: Int, wasLive: Boolean): Boolean {
        // Some phones send zeros while the mic warms up: not recording yet.
        if (!wasLive && (0 until n).none { pcm[it].toInt() != 0 }) return false
        var sum = 0.0
        val floats = FloatArray(n) { i ->
            val v = pcm[i] / 32768f
            sum += v * v
            v
        }
        s.audio.put(floats)
        emit(s, mapOf("type" to "level", "level" to levelOf(sqrt(sum / n))))
        return true
    }

    private fun levelOf(rms: Double): Double =
        ((20 * log10(max(rms, 1e-5)) + 60) / 60).coerceIn(0.0, 1.0)

    private fun fail(s: Session, code: String) {
        Log.e(TAG, "session ${s.id}: $code")
        emit(s, mapOf("type" to "error", "code" to code))
        main.post { if (active === s) active = null }
    }

    private fun emit(s: Session, event: Map<String, Any>) {
        main.post {
            if (!s.cancel) sink?.success(event + ("session" to s.id))
        }
    }

    private companion object {
        const val TAG = "IsharaMoonshine"
        const val RATE = 16000
        const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
        const val CHUNK = 1600 // 100 ms
        const val UPDATE_SAMPLES = 8000 // a partial every 500 ms of audio
        const val POLL_MS = 200L
        const val READ_IDLE_MS = 10L
        const val READER_JOIN_MS = 2000L
        const val PRESS_GRACE_MS = 10_000L
        val END = FloatArray(0)
    }
}
