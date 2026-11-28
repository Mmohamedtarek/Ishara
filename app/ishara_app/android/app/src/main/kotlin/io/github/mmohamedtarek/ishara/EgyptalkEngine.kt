package io.github.mmohamedtarek.ishara

import android.content.res.AssetManager
import android.os.SystemClock
import android.util.Log
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineNemoEncDecCtcModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig

/**
 * The only class that touches sherpa-onnx (DECISIONS TV-24): EgypTalk-ASR-v2,
 * CTC int8, loaded straight from the APK's uncompressed asset (no copy).
 *
 * EgypTalk is not a streaming model: the sentence is one decode of the
 * whole recording after the release. While the mic is held, short
 * windows keep TV-17's silence limit going ([WordWindows]); they are never
 * shown and never the sentence. One decode at a time, never a release under
 * one ([WindowedListen]). No network, no files: audio stays in memory.
 */
internal class EgyptalkEngine private constructor(private val recognizer: OfflineRecognizer) {
    /** As a [LocalRecognizer] for one listen at a time ([WindowedListen]). */
    fun recognizer(): LocalRecognizer = WindowedListen(
        decode = ::decode,
        release = recognizer::release,
        log = { Log.i(TAG, it) },
        now = SystemClock::elapsedRealtime,
    )

    private fun decode(samples: FloatArray): String {
        val stream = recognizer.createStream()
        try {
            stream.acceptWaveform(samples, RATE)
            recognizer.decode(stream)
            return recognizer.getResult(stream).text.trim()
        } finally {
            stream.release()
        }
    }

    companion object {
        private const val TAG = "IsharaEgyptalk"
        private const val RATE = WordWindows.RATE
        private const val THREADS = 4

        /** Loads the model from [assets] (folder `egyptalk` in the APK). */
        fun load(assets: AssetManager, model: String, tokens: String): Pair<EgyptalkEngine?, String?> =
            try {
                val config = OfflineRecognizerConfig(
                    featConfig = FeatureConfig(sampleRate = RATE, featureDim = 80),
                    modelConfig = OfflineModelConfig(
                        nemo = OfflineNemoEncDecCtcModelConfig(model = model),
                        tokens = tokens,
                        numThreads = THREADS,
                        provider = "cpu",
                        debug = false,
                    ),
                    decodingMethod = "greedy_search",
                )
                val recognizer = OfflineRecognizer(assets, config)
                // sherpa-onnx answers a config its JNI can't read with a null
                // handle, not an error: decoding with it would end the app.
                val handle = try {
                    OfflineRecognizer::class.java.getDeclaredField("ptr")
                        .apply { isAccessible = true }
                        .getLong(recognizer)
                } catch (e: Throwable) {
                    // the model is loaded: free it, never leak 132 MB
                    recognizer.release()
                    throw e
                }
                if (handle == 0L) null to "config" else EgyptalkEngine(recognizer) to null
            } catch (e: Throwable) {
                null to e.javaClass.simpleName
            }
    }
}
