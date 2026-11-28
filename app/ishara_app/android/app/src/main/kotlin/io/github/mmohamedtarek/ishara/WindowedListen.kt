package io.github.mmohamedtarek.ishara

import java.util.concurrent.CancellationException
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/**
 * One EgypTalk listen at a time (DECISIONS TV-24), around a [decode] of
 * 16 kHz audio. No Android and no sherpa-onnx: unit-tested on the laptop.
 *
 * - The sentence is one [decode] of the whole recording in [finish].
 * - While the mic is held, [WordWindows] picks windows to decode on a second
 *   thread; a word heard goes to the listen's partial callback (TV-17).
 * - The model is used by one decode at a time, with no time limit: the
 *   final decode, [end] and [free] wait for a running window however long
 *   it takes, so two decodes never overlap and the model is never released
 *   under one.
 * - A window belongs to the listen that started it: one still running when
 *   the next listen begins is dropped.
 * - A recording shorter than [MIN_SAMPLES] is not decoded (empty text).
 */
internal class WindowedListen(
    private val decode: (FloatArray) -> String,
    private val release: () -> Unit,
    private val log: (String) -> Unit,
    private val now: () -> Long,
) : LocalRecognizer {
    private val windows: ExecutorService =
        Executors.newSingleThreadExecutor { Thread(it, "egyptalk-window") }
    private var audio = FloatArray(RATE * 10)
    private var length = 0
    private val ticks = WordWindows()
    private var partial: (String) -> Unit = {}
    private var running: Future<*>? = null
    private val windowMs = mutableListOf<Long>()

    /** Which listen this is: a window from an earlier one is dropped. */
    @Volatile private var listen = 0

    /** Where (samples) the last non-empty window and the last word heard end; -1: none. */
    @Volatile private var lastWordEnd = -1

    @Volatile private var lastHeardEnd = -1

    override fun begin(partial: (String) -> Unit): Boolean {
        waitForWindow()
        listen++
        this.partial = partial
        length = 0
        ticks.reset()
        synchronized(windowMs) { windowMs.clear() }
        lastWordEnd = -1
        lastHeardEnd = -1
        return true
    }

    override fun add(samples: FloatArray): Boolean {
        if (length + samples.size > audio.size) {
            audio = audio.copyOf(maxOf(audio.size * 2, length + samples.size))
        }
        System.arraycopy(samples, 0, audio, length, samples.size)
        length += samples.size
        return true
    }

    override fun update(): Boolean {
        val skippedBefore = ticks.skipped
        val range = ticks.due(length, busy = running?.isDone == false)
        if (ticks.skipped > skippedBefore) log("window skipped: the previous one is still decoding")
        if (range == null) return true
        val window = audio.copyOfRange(range.first, range.last + 1)
        val windowEnd = range.last + 1
        val owner = listen
        val emit = partial
        running = windows.submit {
            val started = now()
            val text = try {
                decode(window)
            } catch (e: Throwable) {
                log("window decode failed: ${e.javaClass.simpleName}")
                null
            }
            val ms = now() - started
            log("window decode $ms ms (${msOf(window.size)} ms of audio)")
            if (owner != listen) {
                log("window of an earlier listen dropped")
                return@submit
            }
            synchronized(windowMs) { windowMs.add(ms) }
            if (!text.isNullOrBlank()) lastWordEnd = windowEnd
            if (text != null && ticks.heard(text)) {
                lastHeardEnd = windowEnd
                emit(text)
            }
        }
        return true
    }

    override fun finish(): String? {
        waitForWindow()
        // TV-17 on the phone, in audio time (the recording includes TV-16's tail)
        log(
            "last non-empty window ends at ${msOf(lastWordEnd)} ms, last word heard " +
                "at ${msOf(lastHeardEnd)} ms, recording ${msOf(length)} ms",
        )
        if (length < MIN_SAMPLES) {
            // sherpa-onnx may end the app on an empty input instead of reporting it
            log("final: ${msOf(length)} ms of audio, not decoded")
            return ""
        }
        val started = now()
        val text = decode(audio.copyOf(length))
        log("final decode ${now() - started} ms (${msOf(length)} ms of audio)")
        return text
    }

    override fun stats(): Map<String, Any> {
        val ms = synchronized(windowMs) { windowMs.sorted() }
        return mapOf(
            "windows" to ms.size,
            "windowsSkipped" to ticks.skipped,
            "windowMsMedian" to (if (ms.isEmpty()) 0L else ms[ms.size / 2]),
            "windowMsMax" to (ms.lastOrNull() ?: 0L),
            "audioMs" to msOf(length),
            "lastWordAudioMs" to msOf(lastWordEnd),
            "lastHeardAudioMs" to msOf(lastHeardEnd),
        )
    }

    override fun end() {
        waitForWindow()
        length = 0
        if (audio.size > RATE * 10) audio = FloatArray(RATE * 10)
    }

    override fun free() {
        waitForWindow()
        windows.shutdown()
        awaitUninterrupted { windows.awaitTermination(1, TimeUnit.MINUTES) }
        release()
    }

    private fun msOf(samples: Int): Long = if (samples < 0) -1L else samples * 1000L / RATE

    /** Until the running window is over, however long: no other decode meanwhile. */
    private fun waitForWindow() {
        val window = running ?: return
        awaitUninterrupted {
            try {
                window.get()
            } catch (e: ExecutionException) {
                // the window's own error: it is over
            } catch (e: CancellationException) {
                // never cancelled; over anyway
            }
            true
        }
        running = null
    }

    /** Runs [done] until it returns true; an interrupt is kept for later, never skips the wait. */
    private fun awaitUninterrupted(done: () -> Boolean) {
        var interrupted = false
        while (true) {
            try {
                if (done()) break
            } catch (e: InterruptedException) {
                interrupted = true
            }
        }
        if (interrupted) Thread.currentThread().interrupt()
    }

    companion object {
        private const val RATE = WordWindows.RATE

        /** Under 0.25 s nothing is decoded: no word is that short. */
        const val MIN_SAMPLES = RATE / 4
    }
}
