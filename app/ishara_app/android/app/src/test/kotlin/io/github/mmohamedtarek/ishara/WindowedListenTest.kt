package io.github.mmohamedtarek.ishara

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * EgypTalk's listen (DECISIONS TV-24) around a fake decoder: one decode at
 * a time with no time limit, never a release under a decode, nothing decoded
 * from an empty recording, windows belong to their listen.
 */
class WindowedListenTest {
    private val rate = WordWindows.RATE

    private class FakeModel {
        val calls = AtomicInteger()
        val running = AtomicInteger()
        val mostAtOnce = AtomicInteger()
        val released = AtomicBoolean()
        val decodingWhenReleased = AtomicBoolean()

        /** Window decodes wait for this. */
        val windowGo = CountDownLatch(1)
        val windowStarted = CountDownLatch(1)
        val log: MutableList<String> = Collections.synchronizedList(mutableListOf())

        fun decode(samples: FloatArray): String {
            calls.incrementAndGet()
            mostAtOnce.accumulateAndGet(running.incrementAndGet(), ::maxOf)
            try {
                if (Thread.currentThread().name == "egyptalk-window") {
                    windowStarted.countDown()
                    windowGo.await()
                    return "مية"
                }
                return "final ${samples.size}"
            } finally {
                running.decrementAndGet()
            }
        }

        fun release() {
            decodingWhenReleased.set(running.get() > 0)
            released.set(true)
        }

        fun listen() = WindowedListen(::decode, ::release, { log.add(it) }, System::currentTimeMillis)
    }

    private fun oneSecond() = FloatArray(rate) { 0.1f }

    @Test
    fun `an empty or very short recording is never decoded`() {
        val model = FakeModel()
        val listen = model.listen()
        listen.begin {}
        assertEquals("", listen.finish())
        listen.end()
        listen.begin {}
        listen.add(FloatArray(WindowedListen.MIN_SAMPLES - 1))
        assertEquals("", listen.finish())
        listen.end()
        assertEquals("sherpa-onnx never gets an empty input", 0, model.calls.get())
        listen.begin {}
        listen.add(FloatArray(WindowedListen.MIN_SAMPLES))
        assertEquals("final ${WindowedListen.MIN_SAMPLES}", listen.finish())
        listen.end()
        listen.free()
    }

    @Test
    fun `the final decode waits for a running window, however long`() {
        val model = FakeModel()
        val listen = model.listen()
        val partials = Collections.synchronizedList(mutableListOf<String>())
        listen.begin { partials.add(it) }
        listen.add(oneSecond())
        listen.update()
        assertTrue(model.windowStarted.await(5, TimeUnit.SECONDS))
        var final: String? = null
        val stop = Thread { final = listen.finish() }
        stop.start()
        stop.join(1500) // longer than any wait that could give up
        assertTrue("finish waits for the window", stop.isAlive)
        assertEquals("no final decode during the window", 1, model.calls.get())
        model.windowGo.countDown()
        stop.join(5000)
        assertEquals("final $rate", final)
        assertEquals("never two decodes at once", 1, model.mostAtOnce.get())
        assertEquals(listOf("مية"), partials)
        listen.end()
        listen.free()
    }

    @Test
    fun `the model is never released under a running window`() {
        val model = FakeModel()
        val listen = model.listen()
        listen.begin {}
        listen.add(oneSecond())
        listen.update()
        assertTrue(model.windowStarted.await(5, TimeUnit.SECONDS))
        val free = Thread { listen.free() }
        free.start()
        free.join(1500)
        assertTrue("free waits for the window", free.isAlive)
        assertFalse(model.released.get())
        model.windowGo.countDown()
        free.join(5000)
        assertTrue(model.released.get())
        assertFalse("released only after the window", model.decodingWhenReleased.get())
    }

    @Test
    fun `a window never reaches the next listen`() {
        val model = FakeModel()
        val listen = model.listen()
        val first = Collections.synchronizedList(mutableListOf<String>())
        val second = Collections.synchronizedList(mutableListOf<String>())
        listen.begin { first.add(it) }
        listen.add(oneSecond())
        listen.update()
        assertTrue(model.windowStarted.await(5, TimeUnit.SECONDS))
        val end = Thread { listen.end() }
        end.start()
        end.join(500)
        assertTrue("end waits for the window", end.isAlive)
        model.windowGo.countDown()
        end.join(5000)
        listen.begin { second.add(it) }
        assertEquals(listOf("مية"), first)
        assertEquals(emptyList<String>(), second)
        assertEquals("", listen.finish())
        listen.end()
        listen.free()
    }

    @Test
    fun `stats say where the last word was heard (TV-17 on the phone)`() {
        val model = FakeModel()
        model.windowGo.countDown()
        val listen = model.listen()
        listen.begin {}
        listen.add(oneSecond())
        listen.update()
        listen.add(oneSecond())
        listen.finish()
        val stats = listen.stats()
        assertEquals(2000L, stats["audioMs"])
        assertEquals(1000L, stats["lastWordAudioMs"])
        assertEquals(1000L, stats["lastHeardAudioMs"])
        assertEquals(1, stats["windows"])
        listen.end()
        listen.free()
    }
}
