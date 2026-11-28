package io.github.mmohamedtarek.ishara

/**
 * One loaded on-device model, driven by [OnDeviceSpeechPlugin]: Moonshine
 * for English (DECISIONS TV-21), EgypTalk for Arabic (TV-24). Every call
 * comes from the plugin's engine thread; one listen at a time.
 */
internal interface LocalRecognizer {
    /** Starts a listen; [partial] gets the text heard so far. False if it can't. */
    fun begin(partial: (String) -> Unit): Boolean

    /** Adds 16 kHz mono samples; false if decoding failed. */
    fun add(samples: FloatArray): Boolean

    /** After each batch of [add]s while the listen is on; false if decoding failed. */
    fun update(): Boolean

    /** The listen's final text, or null if decoding failed. */
    fun finish(): String?

    /** For the final event: how decoding went (logged in Dart). */
    fun stats(): Map<String, Any> = emptyMap()

    /** Always called once after [begin], whatever happened. */
    fun end()

    /** Frees the model. Not used afterwards. */
    fun free()
}
