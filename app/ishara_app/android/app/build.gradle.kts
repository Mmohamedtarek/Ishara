import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Moonshine model (English speech to text, DECISIONS TV-21) -------------
// Moonshine Small streaming English, quantized_26_11_02, for moonshine-voice
// 0.1.6 (MIT). It ships inside the APK but is never committed: the
// `fetchMoonshineModel` task puts it in src/main/assets (git-ignored).
// Pure Gradle (no bash, curl or sha256sum), so it also runs on Windows.

/** One pinned file: name, size in bytes, SHA-256. */
data class PinnedFile(val name: String, val size: Long, val sha256: String)

val moonshineModelVersion = "small-streaming-en/quantized_26_11_02"
val moonshineBaseUrl = "https://download.moonshine.ai/model/$moonshineModelVersion"
val moonshineFiles = listOf(
    PinnedFile("adapter.ort", 2870320, "100d4806a3ba19b739fa9ae5c952e4d5267983090eea4a085e08d3e0bfd6875b"),
    PinnedFile("cross_kv.ort", 5356496, "aa0ed033b7065ef744c36dce00228c708b43f2f2410e8ec782a960105c8595f7"),
    PinnedFile("decoder_kv.ort", 82043616, "e4fae3869851b861177b5e1619c77ec9262365b2747ec322298d11753e88b38d"),
    PinnedFile("encoder.ort", 44148536, "f61486dc7b017cee99196366dcc977a173f45f2f387b0b7977695d0f0565d234"),
    PinnedFile("frontend.model.ort", 26992, "4a8d5ef7e99a5e3011dbf09ffac4176056587f2aec20f885d606b9f55fbed408"),
    PinnedFile("frontend.weights.ort", 7769416, "5379f3dfebe849c6cbacf84f0aa7441956f9572efe1720d44aa267e7dff93056"),
    PinnedFile("streaming_config.json", 512, "26f02b6afb22d60871a5efd85c3d38e569cc0ddb6c5eb6e93d3260152ae8a47a"),
    PinnedFile("tokenizer.bin", 249974, "6884b35fd6377d4c4d32336a0bc152f36b64d1e45b6503683cdc238250a8472d"),
)
val moonshineAssets = file("src/main/assets/moonshine/small-streaming-en")

// --- EgypTalk model (Arabic speech to text, DECISIONS TV-24) ----------------
// EgypTalk-ASR-v2 (NAMAA-Space, CC BY 4.0), CTC branch exported to ONNX and
// int8 by app/tools/egyptalk_export.py, published on this repo's release
// below. Like Moonshine's: inside the APK, uncompressed, never committed.
val egyptalkModelVersion = "model-egyptalk-asr-v2-ctc-int8-r1"
val egyptalkBaseUrl = "https://github.com/Mmohamedtarek/Ishara/releases/download/$egyptalkModelVersion"
val egyptalkFiles = listOf(
    PinnedFile("egyptalk-asr-v2-ctc.int8.onnx", 131652630, "e311a80d77a2c05db0090df0edeae75ce426de2fb5521a0a54a14a15016b585e"),
    PinnedFile("egyptalk-asr-v2-tokens.txt", 12858, "9b938381a19a69bb279cdcfc299419f25a049ea1de192e0d10317274a0f20074"),
)
val egyptalkAssets = file("src/main/assets/egyptalk")

// --- sherpa-onnx (runs EgypTalk, Apache-2.0, DECISIONS TV-24) ---------------
// Not on Maven Central: the AAR comes from k2-fsa's GitHub release, pinned.
// The static-link build has ONNX Runtime 1.28.2 inside libsherpa-onnx-jni.so
// (no libonnxruntime.so, no exported Ort symbols), so it never collides with
// Moonshine's libonnxruntime.so (1.23.2, a minimal build that can't load
// ONNX models). Code, not a model: every build needs it, CI included.
val sherpaOnnxAar = PinnedFile(
    "sherpa-onnx-static-link-onnxruntime-2.0.3.aar",
    39999115,
    "7744a3a8f08f017d59c2d8ed8d9b700345561f5abe9f4e06dc6eaef3a0b977b4",
)
val sherpaOnnxUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.3"
val sherpaOnnxDir = file("libs")

/**
 * Test only (DECISIONS TV-21): `-PmoonshineBrokenModelTest=true` adds the
 * build type `moonshineBrokenTest`, a separate app with one bad byte in the
 * model, to see the fallback to Google on a phone. Off by default.
 */
val moonshineBrokenModelTest =
    providers.gradleProperty("moonshineBrokenModelTest").orNull == "true"

fun sha256Of(f: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    f.inputStream().use { input ->
        val buffer = ByteArray(1 shl 20)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            digest.update(buffer, 0, n)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

fun pinnedFileOk(f: File, want: PinnedFile): Boolean =
    f.isFile && f.length() == want.size && sha256Of(f) == want.sha256

/**
 * The folder a -P...Cache property names, or [default]. A named folder that
 * doesn't exist fails the build instead of downloading again: in
 * `-PegyptalkCache=~/x` the shell doesn't expand `~`, so use `$HOME/x`.
 */
fun cacheFolder(name: String, property: String?, default: File): File {
    if (property == null) return default
    val folder = File(property)
    if (!folder.isDirectory) {
        throw GradleException("-P$name=$property is not a folder (use \$HOME, not ~).")
    }
    return folder
}

/**
 * Puts [want] in [dir]: kept if already right, else copied from [cache] or
 * downloaded from "[baseUrl]/name"; always checked (size and SHA-256), and
 * moved into place only when right.
 */
fun fetchPinned(want: PinnedFile, dir: File, cache: File, baseUrl: String, log: (String) -> Unit) {
    dir.mkdirs()
    val dest = File(dir, want.name)
    if (pinnedFileOk(dest, want)) {
        log("ok          ${want.name}")
        return
    }
    val part = File(dir, want.name + ".part")
    part.delete()
    val cached = File(cache, want.name)
    if (pinnedFileOk(cached, want)) {
        cached.copyTo(part, overwrite = true)
        log("from cache  ${want.name}")
    } else {
        val url = "$baseUrl/${want.name}"
        log("download    $url")
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 30_000
        connection.readTimeout = 60_000
        connection.setRequestProperty("User-Agent", "ishara-build")
        try {
            if (connection.responseCode != 200) {
                throw GradleException("$url answered HTTP ${connection.responseCode}")
            }
            connection.inputStream.use { input ->
                part.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
            }
        } finally {
            connection.disconnect()
        }
    }
    if (!pinnedFileOk(part, want)) {
        part.delete()
        throw GradleException(
            "${want.name}: wrong size or SHA-256 (expected ${want.size} bytes, ${want.sha256}).",
        )
    }
    Files.move(
        part.toPath(),
        dest.toPath(),
        StandardCopyOption.REPLACE_EXISTING,
        StandardCopyOption.ATOMIC_MOVE,
    )
}

val userCache = File(System.getProperty("user.home"), ".cache/ishara")

android {
    namespace = "io.github.mmohamedtarek.ishara"
    // flutter_reactive_ble 5.6.0 (reactive_ble_mobile) requires compiling
    // against API 37. Runtime behaviour (targetSdk) is unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.mmohamedtarek.ishara"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The app checks its copy of the model against these (MoonshineModelStore).
        buildConfigField("String", "MOONSHINE_MODEL_VERSION", "\"$moonshineModelVersion\"")
        buildConfigField(
            "String",
            "MOONSHINE_MODEL_FILES",
            "\"" + moonshineFiles.joinToString(";") { "${it.name}:${it.size}:${it.sha256}" } + "\"",
        )
        // The app checks the APK's EgypTalk files against these (EgyptalkModelCheck).
        buildConfigField("String", "EGYPTALK_MODEL_VERSION", "\"$egyptalkModelVersion\"")
        buildConfigField(
            "String",
            "EGYPTALK_MODEL_FILES",
            "\"" + egyptalkFiles.joinToString(";") { "${it.name}:${it.size}:${it.sha256}" } + "\"",
        )
    }

    // The models are stored uncompressed: the app copies Moonshine's straight
    // out of the APK, and sherpa-onnx maps EgypTalk's in place. Exact names:
    // other assets stay compressed.
    androidResources {
        noCompress += moonshineFiles.map { it.name } + egyptalkFiles.map { it.name }
    }

    packaging {
        jniLibs {
            // sherpa-onnx's 32-bit x86 build: Flutter ships no x86 app, and
            // only there does sherpa bring its own libonnxruntime.so.
            excludes += listOf("lib/x86/libsherpa-onnx-jni.so", "lib/x86/libonnxruntime.so")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
        if (moonshineBrokenModelTest) {
            create("moonshineBrokenTest") {
                initWith(getByName("release"))
                isMinifyEnabled = true
                isShrinkResources = true
                applicationIdSuffix = ".brokenmodeltest"
                matchingFallbacks += listOf("release")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // English speech to text on the phone (MIT; DECISIONS TV-21). Not
    // transitive: OkHttp and WorkManager stay out, so Moonshine's downloader
    // can't run, and R8 removes it (proguard-rules.pro).
    implementation("ai.moonshine:moonshine-voice:0.1.6") {
        isTransitive = false
    }
    // Arabic speech to text on the phone (Apache-2.0; DECISIONS TV-24), put
    // in libs/ (git-ignored) by fetchSherpaOnnx before every build.
    implementation(files(File(sherpaOnnxDir, sherpaOnnxAar.name)))
    // JVM tests of the window rule (WordWindowsTest; EPL-1.0, never in the app)
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}

val fetchMoonshineModel = tasks.register("fetchMoonshineModel") {
    group = "ishara"
    description = "Puts the Moonshine model in src/main/assets and checks every SHA-256 " +
        "(-PmoonshineCache=<folder> reuses a local copy)."
    val cacheProperty = providers.gradleProperty("moonshineCache").orNull
    doLast {
        val cache = cacheFolder(
            "moonshineCache",
            cacheProperty,
            File(
                System.getProperty("user.home"),
                ".cache/moonshine_voice/download.moonshine.ai/model/$moonshineModelVersion",
            ),
        )
        for (want in moonshineFiles) {
            fetchPinned(want, moonshineAssets, cache, moonshineBaseUrl) { logger.lifecycle(it) }
        }
        logger.lifecycle("Moonshine model ready in $moonshineAssets")
    }
}

val checkMoonshineModel = tasks.register("checkMoonshineModel") {
    group = "ishara"
    description = "Fails unless the Moonshine model is in src/main/assets with the right SHA-256."
    doLast {
        val bad = moonshineFiles.filterNot { pinnedFileOk(File(moonshineAssets, it.name), it) }
        if (bad.isNotEmpty()) {
            throw GradleException(
                """
                |Moonshine model missing or wrong in $moonshineAssets:
                |  ${bad.joinToString(", ") { it.name }}
                |A release build ships the English speech model inside the APK (DECISIONS TV-21).
                |Fetch it, then build again:
                |  Linux / macOS:  cd app/ishara_app/android && ./gradlew :app:fetchMoonshineModel
                |  Windows:        cd app\ishara_app\android && gradlew.bat :app:fetchMoonshineModel
                |Add -PmoonshineCache=<folder> to reuse a local copy of the 8 files.
                """.trimMargin(),
            )
        }
    }
}

val fetchEgyptalkModel = tasks.register("fetchEgyptalkModel") {
    group = "ishara"
    description = "Puts the EgypTalk model in src/main/assets and checks every SHA-256 " +
        "(-PegyptalkCache=<folder> reuses a local copy, e.g. egyptalk_export.py's output)."
    val cacheProperty = providers.gradleProperty("egyptalkCache").orNull
    doLast {
        val cache = cacheFolder("egyptalkCache", cacheProperty, File(userCache, "egyptalk/$egyptalkModelVersion"))
        for (want in egyptalkFiles) {
            fetchPinned(want, egyptalkAssets, cache, egyptalkBaseUrl) { logger.lifecycle(it) }
        }
        logger.lifecycle("EgypTalk model ready in $egyptalkAssets")
    }
}

val checkEgyptalkModel = tasks.register("checkEgyptalkModel") {
    group = "ishara"
    description = "Fails unless the EgypTalk model is in src/main/assets with the right SHA-256."
    doLast {
        val bad = egyptalkFiles.filterNot { pinnedFileOk(File(egyptalkAssets, it.name), it) }
        if (bad.isNotEmpty()) {
            throw GradleException(
                """
                |EgypTalk model missing or wrong in $egyptalkAssets:
                |  ${bad.joinToString(", ") { it.name }}
                |A release build ships the Arabic speech model inside the APK (DECISIONS TV-24).
                |Fetch it, then build again:
                |  Linux / macOS:  cd app/ishara_app/android && ./gradlew :app:fetchEgyptalkModel
                |  Windows:        cd app\ishara_app\android && gradlew.bat :app:fetchEgyptalkModel
                |Add -PegyptalkCache=<folder> to reuse a local copy of the 2 files.
                """.trimMargin(),
            )
        }
    }
}

val fetchSherpaOnnx = tasks.register("fetchSherpaOnnx") {
    group = "ishara"
    description = "Puts the pinned sherpa-onnx AAR in libs/ (-PsherpaOnnxCache=<folder> reuses a local copy)."
    val cacheProperty = providers.gradleProperty("sherpaOnnxCache").orNull
    doLast {
        val cache = cacheFolder("sherpaOnnxCache", cacheProperty, File(userCache, "sherpa-onnx"))
        fetchPinned(sherpaOnnxAar, sherpaOnnxDir, cache, sherpaOnnxUrl) { logger.lifecycle(it) }
    }
}

// Release builds need the models; debug builds and CI work without them
// (the language then falls back to Google). Every build needs sherpa-onnx.
tasks.configureEach {
    if (name == "preReleaseBuild" || name == "preMoonshineBrokenTestBuild") {
        dependsOn(checkMoonshineModel, checkEgyptalkModel)
    }
    if (Regex("^pre.*Build$").matches(name)) dependsOn(fetchSherpaOnnx)
}

// AndroidManifest.xml removes ACCESS_NETWORK_STATE without tools:selector (a
// selector keeps the removing entry as a declaration). Only Moonshine's
// downloader asked for it; if any other library declares it, the merge report
// shows that library and the build stops, so nothing is dropped unnoticed.
val manifestLogs = layout.buildDirectory.dir("outputs/logs").get().asFile
tasks.configureEach {
    val variant = Regex("^process(.+)MainManifest$").find(name)?.groupValues?.get(1)
        ?: return@configureEach
    val report = File(manifestLogs, "manifest-merger-${variant.replaceFirstChar { it.lowercase() }}-report.txt")
    doLast {
        if (!report.exists()) throw GradleException("No manifest merge report: $report")
        val lines = report.readLines()
        val start = lines.indexOfFirst { it == "uses-permission#android.permission.ACCESS_NETWORK_STATE" }
        if (start < 0) return@doLast
        val others = lines.drop(start + 1)
            .takeWhile { it.startsWith("\t") || Regex("^(ADDED|MERGED|REJECTED|IMPLIED) ").containsMatchIn(it) }
            .filter { Regex("^(MERGED|REJECTED|IMPLIED) from \\[").containsMatchIn(it) }
            .filterNot { it.contains("[ai.moonshine:moonshine-voice:") }
        if (others.isNotEmpty()) {
            throw GradleException(
                "ACCESS_NETWORK_STATE is removed in AndroidManifest.xml for Moonshine, but another " +
                    "library declares it too:\n  ${others.joinToString("\n  ")}\n" +
                    "Decide whether that library needs it, then change the remove (DECISIONS TV-21).",
            )
        }
    }
}

if (moonshineBrokenModelTest) {
    // Copies of Moonshine's tokenizer.bin and EgypTalk's model with one byte
    // changed (TV-21, TV-24); build-type assets replace the main ones with
    // the same path. Both languages then fall back to Google.
    val brokenAssets = layout.buildDirectory.dir("moonshine-broken-assets").get().asFile
    val prepareBrokenModel = tasks.register("prepareMoonshineBrokenModel") {
        dependsOn(checkMoonshineModel, checkEgyptalkModel)
        outputs.dir(brokenAssets)
        doLast {
            val tokenizer = File(brokenAssets, "moonshine/small-streaming-en/tokenizer.bin")
            tokenizer.parentFile.mkdirs()
            val bytes = File(moonshineAssets, "tokenizer.bin").readBytes()
            bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 0xFF).toByte()
            tokenizer.writeBytes(bytes)
            logger.lifecycle("BROKEN MODEL TEST: one byte changed in $tokenizer")
            // 132 MB: copied, then one byte in the middle changed in place
            val onnx = egyptalkFiles.first { it.name.endsWith(".onnx") }
            val model = File(brokenAssets, "egyptalk/${onnx.name}")
            model.parentFile.mkdirs()
            File(egyptalkAssets, onnx.name).copyTo(model, overwrite = true)
            RandomAccessFile(model, "rw").use { f ->
                f.seek(onnx.size / 2)
                val b = f.read()
                f.seek(onnx.size / 2)
                f.write(b xor 0xFF)
            }
            logger.lifecycle("BROKEN MODEL TEST: one byte changed in $model")
        }
    }
    android.sourceSets.getByName("moonshineBrokenTest").assets.srcDir(brokenAssets)
    // Flutter copies this build type into each plugin with minify on, and
    // R8 then strips the plugin libraries on their own (no keep rules). The
    // plugins (evaluated after :app) get a copy of their own release instead;
    // the app's R8 shrinks the whole APK as in a release build.
    rootProject.subprojects.filter { it != project }.forEach { plugin ->
        plugin.pluginManager.withPlugin("com.android.library") {
            plugin.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
                .buildTypes.maybeCreate("moonshineBrokenTest").apply {
                    initWith(plugin.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java).buildTypes.getByName("release"))
                }
        }
    }
    tasks.configureEach {
        if (name.startsWith("merge") && name.contains("MoonshineBrokenTest") &&
            name.endsWith("Assets")
        ) {
            dependsOn(prepareBrokenModel)
        }
    }
    // Never mixed with a normal release build: that APK must have the real model.
    gradle.taskGraph.whenReady {
        val release = allTasks.filter { it.project == project && it.name == "preReleaseBuild" }
        if (release.isNotEmpty()) {
            throw GradleException(
                "-PmoonshineBrokenModelTest=true builds only :app:assembleMoonshineBrokenTest. " +
                    "Build the release APK in a separate run without it.",
            )
        }
    }
}
