package io.github.mmohamedtarek.ishara

/**
 * Whether an EgypTalk load that never returned (the app ended during it)
 * counts towards turning EgypTalk off (DECISIONS TV-24). No Android: the
 * exit record is passed in, so this is unit-tested on the laptop. Local
 * only: Android's own record of how the app ended, read on the phone.
 *
 * - API 30+: only a crash counts: [REASON_CRASH], [REASON_CRASH_NATIVE],
 *   or [REASON_EXIT_SELF] with a non-zero status (sherpa-onnx's own
 *   `exit(-1)` on a bad model). Swiped away, killed for memory, or any
 *   other reason: not counted.
 * - API 30+ with no record for that process: counted (a crash loop must
 *   end; Android keeps these records, so this should be rare).
 * - Below API 30 there is no record: every ended load counts.
 */
internal object EndedLoadRule {
    /** The values of android.app.ApplicationExitInfo's constants. */
    const val REASON_EXIT_SELF = 1
    const val REASON_CRASH = 4
    const val REASON_CRASH_NATIVE = 5

    /** Android 11, where ApplicationExitInfo starts. */
    const val EXIT_INFO_SDK = 30

    class Decision(val counts: Boolean, val rule: String)

    /** [reason] and [status] of the ended process's exit record, null if none. */
    fun decide(sdk: Int, reason: Int?, status: Int): Decision = when {
        sdk < EXIT_INFO_SDK -> Decision(true, "below API 30: every ended load counts")
        reason == null -> Decision(true, "API 30+, no exit record: counted")
        reason == REASON_CRASH || reason == REASON_CRASH_NATIVE ->
            Decision(true, "API 30+, exit reason $reason (crash): counted")
        reason == REASON_EXIT_SELF && status != 0 ->
            Decision(true, "API 30+, exit reason $reason status $status (exited with an error): counted")
        else -> Decision(false, "API 30+, exit reason $reason status $status (not a crash): not counted")
    }
}
