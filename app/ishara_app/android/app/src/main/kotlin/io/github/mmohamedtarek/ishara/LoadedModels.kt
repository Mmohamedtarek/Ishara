package io.github.mmohamedtarek.ishara

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * The loaded on-device models by name, one at a time (DECISIONS TV-24).
 * No Android: unit-tested on the laptop.
 *
 * Every use of a model (a prepare, cached or not, and every listen) first
 * frees the other loaded models, except one a start was asked for and not
 * yet run: that listen keeps its model. Starts are counted here when asked
 * (main thread) and when run (engine thread), not read from the main
 * thread's session, so the engine thread never sees a stale state.
 * Everything else runs on the plugin's engine thread.
 */
internal class LoadedModels<M : Any>(private val free: (name: String, model: M, why: String) -> Unit) {
    private val loaded = LinkedHashMap<String, M>()
    private val startsWaiting = ConcurrentHashMap<String, AtomicInteger>()

    operator fun get(name: String): M? = loaded[name]

    operator fun set(name: String, model: M) {
        loaded[name] = model
    }

    /** Frees [name]'s model; false if none was loaded. */
    fun free(name: String, why: String): Boolean {
        val model = loaded.remove(name) ?: return false
        free(name, model, why)
        return true
    }

    fun freeAll(why: String) = loaded.keys.toList().forEach { free(it, why) }

    /** A start for [name] was asked for (main thread). */
    fun startAsked(name: String) {
        startsWaiting.getOrPut(name) { AtomicInteger() }.incrementAndGet()
    }

    /** That start runs now (engine thread), once per [startAsked]. */
    fun startRun(name: String) {
        startsWaiting[name]?.updateAndGet { maxOf(0, it - 1) }
    }

    fun startWaiting(name: String): Boolean = (startsWaiting[name]?.get() ?: 0) > 0

    /** Before [name] is used: frees every other model no start is waiting for. */
    fun keepOnly(name: String): List<String> =
        loaded.keys.filter { it != name && !startWaiting(it) }.onEach { free(it, "other language") }
}
