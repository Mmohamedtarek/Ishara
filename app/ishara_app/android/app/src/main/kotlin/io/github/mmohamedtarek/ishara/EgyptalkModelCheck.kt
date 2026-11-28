package io.github.mmohamedtarek.ishara

import android.app.ActivityManager
import android.content.Context
import android.content.res.AssetManager
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.IOException
import java.security.MessageDigest

/**
 * The EgypTalk model inside the APK (DECISIONS TV-24). sherpa-onnx reads it
 * straight from the uncompressed asset, so nothing is copied; but sherpa
 * ends the whole app on a missing or bad file instead of reporting it, so
 * no load happens before this check passes:
 *
 * - every file is in the APK with its size and SHA-256 (all hashes once per
 *   app install and model version, then only the sizes, as Moonshine's copy);
 * - when loads crashed the app twice in a row (a "loading" marker left
 *   behind, judged by [EndedLoadRule]: on API 30+ only a real crash counts,
 *   from Android's own exit record, read on the phone), EgypTalk is not
 *   tried again for this app install: Arabic stays on Google. A load that
 *   returns starts the count again.
 *
 * Runs on the plugin's engine thread, never the UI thread.
 */
internal class EgyptalkModelCheck(private val context: Context) {
    private class ModelFile(val name: String, val size: Long, val sha256: String)

    private val files = BuildConfig.EGYPTALK_MODEL_FILES.split(';').map {
        val (name, size, sha) = it.split(':')
        ModelFile(name, size.toLong(), sha)
    }
    private val root = File(context.filesDir, "egyptalk")
    private val verified = File(root, ".verified")
    private val loading = File(root, ".loading")

    /** The asset paths sherpa-onnx loads. */
    val model = "$ASSETS/${files.first { it.name.endsWith(".onnx") }.name}"
    val tokens = "$ASSETS/${files.first { it.name.endsWith(".txt") }.name}"

    /** Loads that crashed the app in a row before the coming one (set by [ensure]). */
    private var crashes = 0

    fun ensure(): MoonshineModelStore.Outcome {
        crashes = crashesInARow()
        if (crashes >= MAX_CRASHED_LOADS) {
            return MoonshineModelStore.Outcome(
                CRASHED,
                mapOf("message" to "loads crashed the app", "crashes" to crashes),
            )
        }
        val inApk = try {
            context.assets.list(ASSETS)?.toSet().orEmpty()
        } catch (e: IOException) {
            return MoonshineModelStore.Outcome(
                MoonshineModelStore.FAILED,
                mapOf("message" to "assets: ${e.javaClass.simpleName}"),
            )
        }
        val missing = files.map { it.name }.filterNot { it in inApk }
        if (missing.isNotEmpty()) {
            return MoonshineModelStore.Outcome(MoonshineModelStore.MISSING, mapOf("files" to missing))
        }
        val wrongSize = files.filter { sizeOf(it.name) != it.size }.map { it.name }
        if (wrongSize.isNotEmpty()) {
            return MoonshineModelStore.Outcome(MoonshineModelStore.CORRUPT, mapOf("files" to wrongSize))
        }
        if (verified.readTextOrNull() == marker()) {
            return MoonshineModelStore.Outcome(MoonshineModelStore.READY, mapOf("copy" to "none", "check" to "kept"))
        }
        val started = SystemClock.elapsedRealtime()
        val bad = files.filterNot { sha256Of(it.name) == it.sha256 }.map { it.name }
        val verifyMs = SystemClock.elapsedRealtime() - started
        if (bad.isNotEmpty()) {
            return MoonshineModelStore.Outcome(MoonshineModelStore.CORRUPT, mapOf("files" to bad))
        }
        write(verified)
        return MoonshineModelStore.Outcome(
            MoonshineModelStore.READY,
            mapOf("copy" to "none", "check" to "verified", "verifyMs" to verifyMs),
        )
    }

    /** Just before sherpa-onnx loads: left behind if the load ends the app. */
    fun loadStarting() =
        write(loading, "${marker()}\n$crashes\n${Process.myPid()}\n${System.currentTimeMillis()}")

    /**
     * Loads of this app install that crashed the app in a row (0 when
     * none): the count before the last load, plus that load if it never
     * returned and [EndedLoadRule] counts how it ended.
     */
    private fun crashesInARow(): Int {
        val lines = loading.readTextOrNull()?.lines() ?: return 0
        if (lines.firstOrNull() != marker()) return 0
        val before = lines.getOrNull(1)?.toIntOrNull() ?: 0
        val pid = lines.getOrNull(2)?.toIntOrNull()
        if (pid == Process.myPid()) return before // this app run's load: it didn't end the app
        val decision = endedLoad(pid)
        val total = before + if (decision.counts) 1 else 0
        Log.i(TAG, "an earlier load ended the app: ${decision.rule}; crashes in a row: $total")
        return total
    }

    /** How the process [pid] ended, from Android's record (API 30+, on the phone). */
    private fun endedLoad(pid: Int?): EndedLoadRule.Decision {
        val sdk = Build.VERSION.SDK_INT
        if (sdk < Build.VERSION_CODES.R || pid == null) return EndedLoadRule.decide(sdk, null, 0)
        val exit = try {
            context.getSystemService(ActivityManager::class.java)
                ?.getHistoricalProcessExitReasons(context.packageName, pid, 1)
                ?.firstOrNull()
        } catch (e: RuntimeException) {
            Log.w(TAG, "exit record: ${e.javaClass.simpleName}")
            null
        }
        return EndedLoadRule.decide(sdk, exit?.reason, exit?.status ?: 0)
    }

    /** The load returned (loaded or not): the app is still running. */
    fun loadReturned() {
        loading.delete()
    }

    private fun sizeOf(name: String): Long = try {
        // uncompressed assets only: a compressed one throws here
        context.assets.openFd("$ASSETS/$name").use { it.length }
    } catch (e: IOException) {
        -1
    }

    private fun sha256Of(name: String): String? = try {
        val digest = MessageDigest.getInstance("SHA-256")
        context.assets.open("$ASSETS/$name", AssetManager.ACCESS_STREAMING).use { input ->
            val buffer = ByteArray(1 shl 20)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        digest.digest().joinToString("") { "%02x".format(it) }
    } catch (e: IOException) {
        null
    }

    /** Written through a temp file and a rename: never half a marker. */
    private fun write(f: File, text: String = marker()): Boolean = try {
        root.mkdirs()
        val part = File(root, "${f.name}.part")
        part.writeText(text)
        part.renameTo(f)
    } catch (e: IOException) {
        Log.w(TAG, "marker ${f.name}: ${e.javaClass.simpleName}")
        false
    }

    /** This model version and this app install (version and update time). */
    private fun marker(): String {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val version = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return "model=${BuildConfig.EGYPTALK_MODEL_VERSION} app=$version/${info.lastUpdateTime}"
    }

    private fun File.readTextOrNull(): String? = try {
        if (isFile) readText() else null
    } catch (e: IOException) {
        null
    }

    companion object {
        /** Loads crashed the app (this app install): not tried again. */
        const val CRASHED = "crashed"
        private const val MAX_CRASHED_LOADS = 2

        private const val TAG = "IsharaEgyptalk"
        private const val ASSETS = "egyptalk"
    }
}
