package io.github.mmohamedtarek.ishara

import android.content.Context
import android.content.res.AssetManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

/**
 * The Moonshine model's copy in the app's files folder (DECISIONS TV-21).
 *
 * The APK holds the model uncompressed in `assets/moonshine/small-streaming-en`.
 * Moonshine loads files, so the first use copies them to
 * `files/moonshine/small-streaming-en` through a temp folder, checks every
 * SHA-256 and renames the folder into place. A marker in the folder ties the
 * copy to this app install and model version: on normal starts only the
 * sizes are checked; after an app update (or a copy) every SHA-256 is.
 * Runs on the plugin's engine thread, never the UI thread.
 */
internal class MoonshineModelStore(private val context: Context) {
    class Outcome(val status: String, val fields: Map<String, Any?> = emptyMap()) {
        val ready get() = status == READY
    }

    private class ModelFile(val name: String, val size: Long, val sha256: String)

    private val files = BuildConfig.MOONSHINE_MODEL_FILES.split(';').map {
        val (name, size, sha) = it.split(':')
        ModelFile(name, size.toLong(), sha)
    }
    private val root = File(context.filesDir, "moonshine")

    /** The folder Moonshine loads. */
    val dir = File(root, FOLDER)
    private val temp = File(root, ".tmp-$FOLDER")

    /** Makes sure [dir] holds a verified model; [copyAgain] replaces it. */
    fun ensure(copyAgain: Boolean = false): Outcome {
        temp.deleteRecursively() // an interrupted copy
        if (!copyAgain && sizesOk(dir)) {
            if (File(dir, MARKER).readTextOrNull() == marker()) return Outcome(READY, mapOf("copy" to "kept"))
            val started = SystemClock.elapsedRealtime()
            val bad = badFiles(dir)
            val verifyMs = SystemClock.elapsedRealtime() - started
            if (bad.isEmpty() && writeMarker(dir)) {
                return Outcome(READY, mapOf("copy" to "verified", "verifyMs" to verifyMs))
            }
            Log.w(TAG, "model copy failed its check (${bad.joinToString()}), copying again")
        }
        return copy()
    }

    /** Deletes the copy (a model that won't load). */
    fun delete() {
        dir.deleteRecursively()
    }

    /** A full SHA-256 check of the copy: false if any file is damaged. */
    fun intact(): Boolean = badFiles(dir).isEmpty()

    private fun copy(): Outcome {
        val inApk = try {
            context.assets.list(ASSETS)?.toSet().orEmpty()
        } catch (e: IOException) {
            return Outcome(FAILED, mapOf("message" to "assets: ${e.javaClass.simpleName}"))
        }
        val missing = files.map { it.name }.filterNot { it in inApk }
        if (missing.isNotEmpty()) return Outcome(MISSING, mapOf("files" to missing))
        // The old copy is useless now: its space counts as free.
        dir.deleteRecursively()
        val needed = files.sumOf { it.size } + SPACE_MARGIN
        val free = context.filesDir.usableSpace
        if (free < needed) {
            return Outcome(NO_SPACE, mapOf("neededMb" to (needed shr 20), "freeMb" to (free shr 20)))
        }
        return try {
            val started = SystemClock.elapsedRealtime()
            if (!temp.mkdirs()) throw IOException("can't create ${temp.name}")
            for (f in files) copyAsset("$ASSETS/${f.name}", File(temp, f.name))
            val copyMs = SystemClock.elapsedRealtime() - started
            val bad = badFiles(temp)
            val verifyMs = SystemClock.elapsedRealtime() - started - copyMs
            when {
                bad.isNotEmpty() -> {
                    temp.deleteRecursively()
                    Outcome(CORRUPT, mapOf("files" to bad))
                }
                !writeMarker(temp) || !temp.renameTo(dir) -> {
                    temp.deleteRecursively()
                    Outcome(FAILED, mapOf("message" to "rename"))
                }
                else -> Outcome(
                    READY,
                    mapOf("copy" to "copied", "copyMs" to copyMs, "verifyMs" to verifyMs),
                )
            }
        } catch (e: IOException) {
            temp.deleteRecursively()
            Outcome(FAILED, mapOf("message" to "copy: ${e.javaClass.simpleName}"))
        }
    }

    private fun copyAsset(path: String, to: File) {
        context.assets.open(path, AssetManager.ACCESS_STREAMING).use { input ->
            FileOutputStream(to).use { output ->
                input.copyTo(output, 1 shl 20)
                output.fd.sync()
            }
        }
    }

    private fun sizesOk(folder: File): Boolean =
        files.all { File(folder, it.name).length() == it.size }

    /** The files whose size or SHA-256 is wrong. */
    private fun badFiles(folder: File): List<String> = files.filterNot {
        val f = File(folder, it.name)
        f.length() == it.size && sha256(f) == it.sha256
    }.map { it.name }

    private fun sha256(f: File): String? = try {
        val digest = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
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
    private fun writeMarker(folder: File): Boolean = try {
        val part = File(folder, "$MARKER.part")
        part.writeText(marker())
        part.renameTo(File(folder, MARKER))
    } catch (e: IOException) {
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
        return "model=${BuildConfig.MOONSHINE_MODEL_VERSION} app=$version/${info.lastUpdateTime}"
    }

    private fun File.readTextOrNull(): String? = try {
        if (isFile) readText() else null
    } catch (e: IOException) {
        null
    }

    companion object {
        const val READY = "ready"

        /** Not in this APK (debug builds and CI without the model). */
        const val MISSING = "missing"
        const val NO_SPACE = "no_space"

        /** The APK's copy is damaged. */
        const val CORRUPT = "corrupt"
        const val FAILED = "failed"

        private const val TAG = "IsharaMoonshine"
        private const val FOLDER = "small-streaming-en"
        private const val ASSETS = "moonshine/$FOLDER"
        private const val MARKER = ".verified"

        /** Room left for the rest of the app after the copy. */
        private const val SPACE_MARGIN = 32L shl 20
    }
}
