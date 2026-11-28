package io.github.mmohamedtarek.ishara

import ai.moonshine.voice.JNI
import ai.moonshine.voice.Transcript
import java.io.File

/**
 * The only class that touches Moonshine (DECISIONS TV-21). Moonshine needs
 * API 26: [OnDeviceSpeechPlugin] never uses this class below it.
 *
 * Calls Moonshine's JNI directly: no downloader, no network, no files besides
 * the model folder. Every call runs on the plugin's engine thread.
 */
internal class MoonshineEngine private constructor(private val handle: Int) {
    /** Starts a stream; returns its id, or a negative error. */
    fun startStream(): Int {
        val stream = JNI.moonshineCreateStream(handle, 0)
        if (stream < 0) return stream
        if (JNI.moonshineStartStream(handle, stream) != JNI.MOONSHINE_ERROR_NONE) {
            JNI.moonshineFreeStream(handle, stream)
            return -1
        }
        return stream
    }

    fun addAudio(stream: Int, samples: FloatArray, rate: Int): Boolean =
        JNI.moonshineAddAudioToStream(handle, stream, samples, rate, 0) == JNI.MOONSHINE_ERROR_NONE

    /** The text so far, or null if decoding failed. */
    fun text(stream: Int): String? = JNI.moonshineTranscribeStream(handle, stream, 0)?.let(::textOf)

    /** Ends [stream]; its final text, or null if decoding failed. */
    fun finish(stream: Int): String? {
        if (JNI.moonshineStopStream(handle, stream) != JNI.MOONSHINE_ERROR_NONE) return null
        return text(stream)
    }

    fun freeStream(stream: Int) {
        JNI.moonshineFreeStream(handle, stream)
    }

    fun free() = JNI.moonshineFreeTranscriber(handle)

    private fun textOf(t: Transcript): String =
        t.lines.orEmpty().mapNotNull { it.text?.trim()?.ifEmpty { null } }.joinToString(" ")

    /** As a [LocalRecognizer]: a streaming listen, a partial every 500 ms of audio. */
    fun recognizer(rate: Int): LocalRecognizer = object : LocalRecognizer {
        private var stream = -1
        private var partial: (String) -> Unit = {}
        private var sinceUpdate = 0
        private var shown = ""

        override fun begin(partial: (String) -> Unit): Boolean {
            this.partial = partial
            sinceUpdate = 0
            shown = ""
            stream = startStream()
            return stream >= 0
        }

        override fun add(samples: FloatArray): Boolean {
            if (!addAudio(stream, samples, rate)) return false
            sinceUpdate += samples.size
            return true
        }

        override fun update(): Boolean {
            if (sinceUpdate < UPDATE_SAMPLES) return true
            sinceUpdate = 0
            val text = text(stream) ?: return false
            if (text != shown) {
                shown = text
                partial(text)
            }
            return true
        }

        override fun finish(): String? = finish(stream)

        override fun end() {
            if (stream >= 0) freeStream(stream)
            stream = -1
        }

        override fun free() = this@MoonshineEngine.free()
    }

    companion object {
        /** A partial every 500 ms of audio. */
        private const val UPDATE_SAMPLES = 8000

        /** Loads Moonshine Small streaming from [dir]: the engine, or an error. */
        fun load(dir: File): Pair<MoonshineEngine?, String?> = try {
            JNI.ensureLibraryLoaded()
            val handle = JNI.moonshineLoadTranscriberFromFiles(
                dir.path,
                JNI.MOONSHINE_MODEL_ARCH_SMALL_STREAMING,
                emptyArray<Any>(),
            )
            if (handle < 0) {
                null to (JNI.moonshineErrorToString(handle) ?: "error $handle")
            } else {
                MoonshineEngine(handle) to null
            }
        } catch (e: Throwable) {
            null to e.javaClass.simpleName
        }
    }
}
