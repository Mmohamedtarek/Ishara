package io.github.mmohamedtarek.ishara

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** One on-device model loaded at a time (DECISIONS TV-24). */
class LoadedModelsTest {
    private val freed = mutableListOf<String>()
    private val models = LoadedModels<String> { name, _, why -> freed.add("$name: $why") }

    @Test
    fun `using one model frees the other, also when it is loaded already`() {
        models["moonshine"] = "en"
        models["egyptalk"] = "ar" // both loaded (e.g. a start kept one)
        assertEquals(listOf("moonshine"), models.keepOnly("egyptalk"))
        assertEquals(listOf("moonshine: other language"), freed)
        assertNull(models["moonshine"])
        assertEquals("ar", models["egyptalk"])
        assertEquals(emptyList<String>(), models.keepOnly("egyptalk"))
    }

    @Test
    fun `a model a start is waiting for is kept until that listen runs`() {
        models["moonshine"] = "en"
        models.startAsked("moonshine")
        assertEquals(emptyList<String>(), models.keepOnly("egyptalk"))
        models.startRun("moonshine")
        assertEquals(listOf("moonshine"), models.keepOnly("egyptalk"))
    }

    @Test
    fun `starts are counted, never below zero`() {
        models["moonshine"] = "en"
        models.startAsked("moonshine")
        models.startAsked("moonshine")
        models.startRun("moonshine")
        assertEquals(emptyList<String>(), models.keepOnly("egyptalk"))
        models.startRun("moonshine")
        models.startRun("moonshine")
        models.startAsked("moonshine")
        assertEquals("one waiting start after an extra run", emptyList<String>(), models.keepOnly("egyptalk"))
    }

    @Test
    fun `free and freeAll`() {
        models["moonshine"] = "en"
        models["egyptalk"] = "ar"
        assertEquals(true, models.free("egyptalk", "trim"))
        assertEquals(false, models.free("egyptalk", "trim"))
        models.freeAll("detached")
        assertEquals(listOf("egyptalk: trim", "moonshine: detached"), freed)
    }
}
