package io.github.mmohamedtarek.ishara

import ai.moonshine.voice.JNI
import ai.moonshine.voice.Transcript
import java.io.File

/**
 * The only class that touches Moonshine (DECISIONS TV-21). Moonshine needs
 * API 26: [MoonshineSpeechPlugin] never uses this class below it.
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

    companion object {
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
