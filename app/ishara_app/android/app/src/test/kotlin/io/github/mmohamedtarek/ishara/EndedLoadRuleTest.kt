package io.github.mmohamedtarek.ishara

import io.github.mmohamedtarek.ishara.EndedLoadRule.REASON_CRASH
import io.github.mmohamedtarek.ishara.EndedLoadRule.REASON_CRASH_NATIVE
import io.github.mmohamedtarek.ishara.EndedLoadRule.REASON_EXIT_SELF
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which ended EgypTalk loads count towards turning it off (DECISIONS TV-24). */
class EndedLoadRuleTest {
    @Test
    fun `the reasons match Android's ApplicationExitInfo`() {
        assertEquals(android.app.ApplicationExitInfo.REASON_EXIT_SELF, REASON_EXIT_SELF)
        assertEquals(android.app.ApplicationExitInfo.REASON_CRASH, REASON_CRASH)
        assertEquals(android.app.ApplicationExitInfo.REASON_CRASH_NATIVE, REASON_CRASH_NATIVE)
    }

    @Test
    fun `API 30+ counts only crashes`() {
        assertTrue(EndedLoadRule.decide(34, REASON_CRASH_NATIVE, 6).counts)
        assertTrue(EndedLoadRule.decide(30, REASON_CRASH, 0).counts)
        assertTrue("sherpa-onnx's exit(-1)", EndedLoadRule.decide(34, REASON_EXIT_SELF, 255).counts)
        assertFalse(EndedLoadRule.decide(34, REASON_EXIT_SELF, 0).counts)
        val notCrashes = listOf(
            android.app.ApplicationExitInfo.REASON_USER_REQUESTED, // swiped away, force-stopped
            android.app.ApplicationExitInfo.REASON_LOW_MEMORY,
            android.app.ApplicationExitInfo.REASON_SIGNALED, // killed by the system
            android.app.ApplicationExitInfo.REASON_OTHER,
        )
        for (reason in notCrashes) {
            val d = EndedLoadRule.decide(34, reason, 9)
            assertFalse("reason $reason", d.counts)
            assertTrue(d.rule, d.rule.contains("not counted"))
        }
    }

    @Test
    fun `API 30+ with no record counts, and below 30 every ended load counts`() {
        assertTrue(EndedLoadRule.decide(31, null, 0).counts)
        val old = EndedLoadRule.decide(29, null, 0)
        assertTrue(old.counts)
        assertTrue(old.rule, old.rule.startsWith("below API 30"))
        assertTrue("no record is read below 30", EndedLoadRule.decide(29, 10, 0).counts)
    }
}
