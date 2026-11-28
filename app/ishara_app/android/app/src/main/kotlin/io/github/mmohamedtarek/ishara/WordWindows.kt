package io.github.mmohamedtarek.ishara

/**
 * When EgypTalk decodes a window while the mic is held, and when that
 * window means "a word was just heard" (TV-17's silence limit, DECISIONS
 * TV-24). No Android and no sherpa-onnx: unit-tested on the laptop.
 *
 * A window is due every [every] samples and is the last [size] samples. A
 * tick that comes while the previous window still decodes is skipped (two
 * decodes never overlap); the next window then starts where the last one
 * decoded ended, minus the usual overlap (at most [MAX] long), so no audio
 * between them is left out. A window is a word heard only when its text is
 * non-empty and differs from the previous window's text (an empty window
 * counts, so the same word said again after a pause is heard again). A word
 * that ended at sample T is in no window due after T + [size]: with 1.5 s
 * windows and no skipped tick, the listen ends at most 6.5 s after the last
 * word plus that window's decode.
 */
internal class WordWindows(private val every: Int = EVERY, private val size: Int = SIZE) {
    private var tickAt = 0
    private var decodedTo = 0
    private var last = ""

    /** Ticks due while the previous window was still decoding (not decoded). */
    var skipped = 0
        private set

    fun reset() {
        tickAt = 0
        decodedTo = 0
        skipped = 0
        synchronized(this) { last = "" }
    }

    /**
     * [length] samples recorded so far; [busy] while the previous window
     * still decodes. The samples to decode now, or null.
     */
    fun due(length: Int, busy: Boolean): IntRange? {
        if (length - tickAt < every) return null
        tickAt = length
        if (busy) {
            skipped++
            return null
        }
        val overlap = size - every
        val from = maxOf(0, length - MAX, minOf(length - size, decodedTo - overlap))
        decodedTo = length
        return from until length
    }

    /** A window's text (from the window thread): true when a word was just heard. */
    @Synchronized
    fun heard(text: String): Boolean {
        val t = text.trim()
        val heard = t.isNotEmpty() && t != last
        last = t
        return heard
    }

    companion object {
        /** 16 kHz mono. */
        const val RATE = 16000

        /** A window every 1 s of audio, of the last 1.5 s (TV-17). */
        const val EVERY = RATE
        const val SIZE = RATE * 3 / 2

        /** The longest window, after skipped ticks: TV-17's 5 s. */
        const val MAX = RATE * 5
    }
}
