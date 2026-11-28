package io.github.mmohamedtarek.ishara

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * TV-17 with EgypTalk (DECISIONS TV-24): the silence limit after the last
 * word. Simulates the plugin (100 ms mic chunks, an update after each) and
 * talk_speech_controller's 5 s limit, re-armed by every partial; windows
 * decode instantly here (the phone adds one 1.5 s window's decode time).
 */
class WordWindowsTest {
    private val rate = 16000
    private val chunk = 1600
    private val limit = 5 * rate

    /** Where the listen auto-stops (samples), or null if it never does before [until]. */
    private fun autoStop(text: (IntRange) -> String, until: Int): Int? {
        val ticks = WordWindows()
        var armedAt = 0 // the mic came on
        var length = 0
        while (length < until) {
            length += chunk
            ticks.due(length, busy = false)?.let { range ->
                if (ticks.heard(text(range))) armedAt = range.last + 1
            }
            if (length - armedAt >= limit) return armedAt + limit
        }
        return null
    }

    /** A word in [from, to): the model hears something in any window touching it. */
    private fun word(from: Int, to: Int): (IntRange) -> String = { r ->
        if (r.first < to && r.last >= from) "word ${maxOf(r.first, from)}..${minOf(r.last + 1, to)}" else ""
    }

    @Test
    fun `a word then silence ends the listen within 6_5 s of the word`() {
        var worst = 0
        // the word's end at every 50 ms over a whole window period
        for (step in 0 until 20) {
            val end = 2 * rate + step * rate / 20
            val stop = autoStop(word(end - 8000, end), until = 20 * rate)!!
            worst = maxOf(worst, stop - end)
        }
        assertTrue("worst case ${worst * 1000 / rate} ms", worst <= rate * 13 / 2)
        assertTrue("never before the 5 s limit", worst >= limit)
    }

    @Test
    fun `the same text again in the next window is not a word heard`() {
        val ticks = WordWindows()
        assertTrue(ticks.heard("مية"))
        assertTrue(!ticks.heard("مية"))
        assertTrue(!ticks.heard("  "))
        assertTrue("after a pause, the same word is heard again", ticks.heard("مية"))
    }

    @Test
    fun `speech that goes on never hits the limit`() {
        val talking = 15 * rate
        assertNull(autoStop({ r -> if (r.first < talking) "word ${r.first}" else "" }, until = talking))
    }

    @Test
    fun `a tick while the previous window decodes is skipped, not delayed`() {
        val ticks = WordWindows()
        assertEquals("the app's window", rate * 3 / 2, WordWindows.SIZE)
        assertEquals(rate, WordWindows.EVERY)
        assertNull(ticks.due(rate - 1, busy = false))
        assertNull(ticks.due(rate, busy = true))
        assertEquals(1, ticks.skipped)
        assertNull("the next window waits for the next tick", ticks.due(rate + chunk, busy = false))
        assertEquals("nothing decoded yet: from the start", 0 until 2 * rate, ticks.due(2 * rate, busy = false))
        ticks.reset()
        assertEquals(0, ticks.skipped)
        assertEquals(0 until rate, ticks.due(rate, busy = false))
    }

    @Test
    fun `after a skipped tick the next window covers the audio since the last one`() {
        val ticks = WordWindows()
        assertEquals(0 until rate, ticks.due(rate, busy = false))
        assertNull(ticks.due(2 * rate, busy = true))
        assertEquals("from the last window's end minus the overlap", rate / 2 until 3 * rate, ticks.due(3 * rate, busy = false))
        assertEquals("back to 1.5 s", 5 * rate / 2 until 4 * rate, ticks.due(4 * rate, busy = false))
        for (t in 5..12) assertNull(ticks.due(t * rate, busy = true))
        assertEquals("never longer than 5 s", 8 * rate until 13 * rate, ticks.due(13 * rate, busy = false))
    }

    @Test
    fun `on a slow phone a short word between two windows is still heard`() {
        // each window takes 1.2 s to decode: every other tick is skipped
        val decodeSamples = rate * 6 / 5
        val word = 3 * rate until 3 * rate + rate * 2 / 5 // a short reply at 3.0-3.4 s
        val ticks = WordWindows()
        var busyUntil = 0
        var heardAt: Int? = null
        var length = 0
        while (length < 8 * rate) {
            length += chunk
            ticks.due(length, busy = length < busyUntil)?.let { r ->
                busyUntil = length + decodeSamples
                val text = if (r.first < word.last + 1 && r.last >= word.first) "لا" else ""
                if (ticks.heard(text) && heardAt == null) heardAt = r.last + 1
            }
        }
        assertTrue("skipped ticks: ${ticks.skipped}", ticks.skipped > 0)
        assertTrue("the word was never in a decoded window", heardAt != null)
    }
}
