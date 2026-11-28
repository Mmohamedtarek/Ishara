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
 * Speech to text on the phone: English with Moonshine Small (DECISIONS
 * TV-21), Arabic with EgypTalk through sherpa-onnx (TV-24), one channel
 * pair per model.
 *
 * Moonshine's model ships in the APK and is copied to the files folder on
 * first use ([MoonshineModelStore]); EgypTalk's is read straight from the
 * APK after a check ([EgyptalkModelCheck]). The engines are only touched
 * through [MoonshineEngine] and [EgyptalkEngine], Moonshine never below API
 * 26. One engine thread runs every load and listen, so only one model is
 * loaded at a time (loading one frees the other first) and a model is never
 * freed during a listen. Audio stays in memory and is never saved; nothing
 * here uses the network. Under memory pressure the loaded model is freed
 * when no listen is on, and loaded again on the next use.
 */
class OnDeviceSpeechPlugin : FlutterPlugin {
    /**
     * Loads a model: the recognizer, or why not ([status]). [pssBefore] and
     * [started] are taken just before the load (after any copy or check).
     */
    private class Opened(
        val recognizer: LocalRecognizer?,
        val status: String,
        val fields: Map<String, Any?>,
        val pssBefore: Long = 0,
        val started: Long = 0,
    )

    /** One model, its channels and its state (engine thread unless noted). */
    private inner class Slot(
        val name: String,
        val tag: String,
        val minSdk: Int,
        val open: () -> Opened,
    ) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
        var methods: MethodChannel? = null
        var events: EventChannel? = null

        /** Main thread only. */
        var sink: EventChannel.EventSink? = null

        /** Why the model can't be used in this app run. */
        var unusable: Map<String, Any?>? = null

        /** When a prepare last answered "ready": a press starts next. */
        var readyAt = 0L

        fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
            methods = MethodChannel(binding.binaryMessenger, "ishara/$name").also {
                it.setMethodCallHandler(this)
            }
            events = EventChannel(binding.binaryMessenger, "ishara/$name/events").also {
                it.setStreamHandler(this)
            }
        }

        fun detach() {
            methods?.setMethodCallHandler(null)
            events?.setStreamHandler(null)
            methods = null
            events = null
            sink = null
        }

        override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
            sink = eventSink
        }

        override fun onCancel(arguments: Any?) {
            sink = null
            // nobody is listening: never leave the mic open
            if (active?.slot === this) cancelActive()
        }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) =
            handle(this, call, result)
    }

    private inner class Session(val id: Int, val slot: Slot) {
        @Volatile var stop = false
        @Volatile var cancel = false
        @Volatile var micError: String? = null

        /** The recognizer got audio from this session. */
        @Volatile var fed = false
        val audio = LinkedBlockingQueue<FloatArray>()
    }

    private lateinit var context: Context
    private lateinit var store: MoonshineModelStore
    private lateinit var egyptalkCheck: EgyptalkModelCheck
    private val main = Handler(Looper.getMainLooper())

    /** Copies and loads the models and runs one session at a time. */
    private val engine = Executors.newSingleThreadExecutor { Thread(it, "on-device-stt") }

    private val moonshine = Slot("moonshine", "IsharaMoonshine", Build.VERSION_CODES.O) { openMoonshine() }
    private val egyptalk = Slot("egyptalk", "IsharaEgyptalk", Build.VERSION_CODES.N) { openEgyptalk() }
    private val slots = listOf(moonshine, egyptalk)

    /** The loaded models by slot name, one at a time (engine thread). */
    private val models = LoadedModels<LocalRecognizer> { name, model, why ->
        model.free()
        Log.i(slots.first { it.name == name }.tag, "model freed ($why)")
    }

    /** Only set on the main thread. */
    @Volatile private var active: Session? = null

    private val memory = object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) {
            @Suppress("DEPRECATION") // still sent below API 34
            val pressure = level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL
            if (pressure) slots.forEach { freeWhenIdle(it, "trim level $level") }
        }

        override fun onConfigurationChanged(newConfig: Configuration) = Unit

        @Deprecated("Still sent on old phones")
        override fun onLowMemory() = slots.forEach { freeWhenIdle(it, "low memory") }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        store = MoonshineModelStore(context)
        egyptalkCheck = EgyptalkModelCheck(context)
        context.registerComponentCallbacks(memory)
        slots.forEach { it.attach(binding) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context.unregisterComponentCallbacks(memory)
        slots.forEach { it.detach() }
        cancelActive()
        engine.execute { models.freeAll("detached") }
        engine.shutdown()
    }

    private fun cancelActive() {
        active?.cancel = true
        active = null
    }

    private fun handle(slot: Slot, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                // Never cancels a listen: a preload (Talk opened or resumed)
                // can arrive while one is on. A session left by a Dart hot
                // restart ends at the next "start".
                engine.execute {
                    val answer = safePrepare(slot)
                    if (answer["status"] == "ready") slot.readyAt = SystemClock.elapsedRealtime()
                    main.post { result.success(answer) }
                }
            }
            "start" -> {
                val session = Session(call.argument<Int>("session") ?: -1, slot)
                cancelActive()
                active = session
                models.startAsked(slot.name) // its model is kept until the listen runs
                engine.execute { runSession(session) }
                result.success(null)
            }
            "stop" -> {
                active?.takeIf { it.slot === slot && it.id == call.argument<Int>("session") }
                    ?.stop = true
                result.success(null)
            }
            "cancel" -> {
                val session = active?.takeIf {
                    it.slot === slot && it.id == call.argument<Int>("session")
                }
                session?.cancel = true
                if (session != null) active = null
                result.success(null)
            }
            "memory" -> Thread({
                val answer = memoryNow()
                main.post { result.success(answer) }
            }, "on-device-stt-memory").start()
            "debugNotice" -> {
                // Debug builds only: says the language is not on its model.
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
    private fun safePrepare(slot: Slot): Map<String, Any?> = try {
        prepare(slot)
    } catch (t: Throwable) {
        Log.e(slot.tag, "prepare failed", t)
        mapOf("status" to "failed", "message" to "prepare: ${t.javaClass.simpleName}")
    }

    /** On [engine]: makes [slot]'s model usable and loads it. */
    private fun prepare(slot: Slot): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < slot.minSdk) {
            return mapOf("status" to "unsupported", "message" to "API ${Build.VERSION.SDK_INT}")
        }
        slot.unusable?.let { return it }
        // One model at a time, also when this one is loaded already: the
        // other language's goes first. Never during a listen (listens run on
        // this thread), and a start already asked for keeps its model.
        models.keepOnly(slot.name)
        if (models[slot.name] != null) return mapOf("status" to "ready", "cached" to true)
        val opened = slot.open()
        if (opened.recognizer == null) return remember(slot, opened.status, opened.fields)
        models[slot.name] = opened.recognizer
        val loadMs = SystemClock.elapsedRealtime() - opened.started
        val pssAfter = Debug.getPss()
        Log.i(
            slot.tag,
            "model loaded in $loadMs ms (${opened.fields}), PSS ${opened.pssBefore} -> $pssAfter kB",
        )
        return mapOf(
            "status" to "ready",
            "cached" to false,
            "loadMs" to loadMs,
            "pssBeforeKb" to opened.pssBefore,
            "pssAfterKb" to pssAfter,
            "nativeHeapKb" to Debug.getNativeHeapAllocatedSize() / 1024,
        ) + opened.fields
    }

    /** Moonshine (TV-21): copy (first use), load, copy again only if damaged. */
    private fun openMoonshine(): Opened {
        var copy = store.ensure()
        if (!copy.ready) return Opened(null, copy.status, copy.fields)
        val pssBefore = Debug.getPss()
        val started = SystemClock.elapsedRealtime()
        var (loaded, error) = MoonshineEngine.load(store.dir)
        // A copy that won't load: copy it again once, then give up. Only when
        // the files may be damaged: a copy just made or just hash-checked (or
        // one that passes the check now) is fine, so the cause is elsewhere
        // (e.g. memory) and copying 142 MB again on every start can't help.
        if (loaded == null && copy.fields["copy"] == "kept" && !store.intact()) {
            Log.w(moonshine.tag, "model failed to load ($error) and is damaged, copying it again")
            store.delete()
            copy = store.ensure(copyAgain = true)
            if (!copy.ready) return Opened(null, copy.status, copy.fields)
            val again = MoonshineEngine.load(store.dir)
            loaded = again.first
            error = again.second
        }
        if (loaded == null) return Opened(null, "failed", mapOf("message" to error))
        return Opened(loaded.recognizer(RATE), "ready", copy.fields, pssBefore, started)
    }

    /** EgypTalk (TV-24): checked in the APK, loaded from it (no copy). */
    private fun openEgyptalk(): Opened {
        val check = egyptalkCheck.ensure()
        if (!check.ready) return Opened(null, check.status, check.fields)
        val pssBefore = Debug.getPss()
        val started = SystemClock.elapsedRealtime()
        egyptalkCheck.loadStarting()
        val (loaded, error) = try {
            EgyptalkEngine.load(context.assets, egyptalkCheck.model, egyptalkCheck.tokens)
        } finally {
            egyptalkCheck.loadReturned()
        }
        if (loaded == null) return Opened(null, "failed", mapOf("message" to error))
        return Opened(loaded.recognizer(), "ready", check.fields, pssBefore, started)
    }

    /** Not usable: kept for this app run, except "no space" (it may change). */
    private fun remember(slot: Slot, status: String, fields: Map<String, Any?>): Map<String, Any?> {
        val answer = mapOf("status" to status) + fields
        Log.e(slot.tag, "model not usable: $answer")
        if (status != MoonshineModelStore.NO_SPACE) slot.unusable = answer
        return answer
    }

    /** Frees [slot]'s model under memory pressure, never during a listen. */
    private fun freeWhenIdle(slot: Slot, why: String) {
        try {
            engine.execute {
                if (models[slot.name] == null) return@execute
                if (active != null || models.startWaiting(slot.name)) {
                    Log.i(slot.tag, "model kept ($why): a listen is on")
                    return@execute
                }
                // A press was just told "ready": its start follows, and a
                // reload inside the listen would lose its first words.
                if (SystemClock.elapsedRealtime() - slot.readyAt < PRESS_GRACE_MS) {
                    Log.i(slot.tag, "model kept ($why): a press is starting")
                    return@execute
                }
                models.free(slot.name, why)
            }
        } catch (e: RejectedExecutionException) {
            // detached
        }
    }

    @SuppressLint("MissingPermission") // checked just before
    private fun runSession(s: Session) {
        val slot = s.slot
        models.startRun(slot.name)
        if (s.cancel) return
        models.keepOnly(slot.name)
        // Freed under memory pressure since the prepare: load it again.
        val rec = models[slot.name] ?: run {
            safePrepare(slot)
            models[slot.name]
        } ?: return fail(s, "model_not_loaded")
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return fail(s, "permission")
        }
        var record: AudioRecord? = null
        var begun = false
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
            begun = rec.begin { text -> emit(s, mapOf("type" to "partial", "text" to text)) }
            if (!begun) return fail(s, "stream_start")
            val mic: AudioRecord = record
            val thread = Thread({ readMic(s, mic) }, "on-device-stt-mic")
            thread.start()
            reader = thread
            record = null // from here the reader thread owns and releases it
            if (!feed(s, rec)) {
                if (!s.cancel) fail(s, "decode")
                return
            }
            reader.join(READER_JOIN_MS)
            if (s.cancel) return
            s.micError?.let {
                // Words already captured are still decoded; the mic is closed.
                if (!s.fed) return fail(s, it)
                Log.w(slot.tag, "session ${s.id}: mic ended early ($it)")
            }

            val started = SystemClock.elapsedRealtime()
            val final = rec.finish() ?: return fail(s, "decode")
            val decodeMs = SystemClock.elapsedRealtime() - started
            emit(s, mapOf("type" to "final", "text" to final, "decodeMs" to decodeMs) + rec.stats())
            main.post { if (active === s) active = null }
        } catch (e: Throwable) {
            Log.e(slot.tag, "session failed: ${e.javaClass.simpleName}")
            fail(s, "engine")
        } finally {
            s.stop = true // the reader ends and releases the mic, whatever happened
            record?.release()
            reader?.join(READER_JOIN_MS)
            if (begun) rec.end()
        }
    }

    /** Feeds the mic to the recognizer until it ends; false if decoding failed. */
    private fun feed(s: Session, rec: LocalRecognizer): Boolean {
        while (true) {
            val first = s.audio.poll(POLL_MS, TimeUnit.MILLISECONDS) ?: continue
            if (first === END) return true
            if (s.cancel) continue // keep draining until the reader's END
            var chunk: FloatArray? = first
            while (chunk != null) {
                if (chunk === END) return true
                if (!rec.add(chunk)) return false
                s.fed = true
                chunk = s.audio.poll()
            }
            if (!s.cancel && !rec.update()) return false
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
            Log.e(s.slot.tag, "mic failed: ${e.javaClass.simpleName}")
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
        Log.e(s.slot.tag, "session ${s.id}: $code")
        emit(s, mapOf("type" to "error", "code" to code))
        main.post { if (active === s) active = null }
    }

    private fun emit(s: Session, event: Map<String, Any>) {
        main.post {
            if (!s.cancel) s.slot.sink?.success(event + ("session" to s.id))
        }
    }

    private companion object {
        const val RATE = 16000
        const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
        const val CHUNK = 1600 // 100 ms
        const val POLL_MS = 200L
        const val READ_IDLE_MS = 10L
        const val READER_JOIN_MS = 2000L
        const val PRESS_GRACE_MS = 10_000L
        val END = FloatArray(0)
    }
}
