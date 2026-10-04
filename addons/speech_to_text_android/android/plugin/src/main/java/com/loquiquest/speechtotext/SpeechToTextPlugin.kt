package com.loquiquest.speechtotext

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class SpeechToTextPlugin(godot: Godot) : GodotPlugin(godot) {
    private var speechRecognizer: SpeechRecognizer? = null
    private var languageTag: String = "en-US"
    private var listening: Boolean = false

    override fun getPluginName(): String = "SpeechToText"

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        return mutableSetOf(
            SignalInfo("listening_completed", String::class.java),
            SignalInfo("error", Integer::class.java),
        )
    }

    @UsedByGodot
    fun set_language(lang: String) {
        languageTag = if (lang.isBlank()) "en-US" else lang
    }

    @UsedByGodot
    fun listen() {
        runOnHostThread {
            val host = activity
            if (host == null) {
                emitSignal("error", -1)
                return@runOnHostThread
            }
            if (host.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                host.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
                emitSignal("error", -1)
                return@runOnHostThread
            }
            if (!SpeechRecognizer.isRecognitionAvailable(host)) {
                emitSignal("error", -1)
                return@runOnHostThread
            }
            destroyRecognizer()
            val recognizer = SpeechRecognizer.createSpeechRecognizer(host)
            speechRecognizer = recognizer
            recognizer.setRecognitionListener(listener)
            listening = true
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            recognizer.startListening(intent)
        }
    }

    @UsedByGodot
    fun stop() {
        runOnHostThread {
            listening = false
            speechRecognizer?.stopListening()
        }
    }

    override fun onMainDestroy() {
        listening = false
        destroyRecognizer()
    }

    private fun destroyRecognizer() {
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
            if (!listening) {
                return
            }
            listening = false
            val code = if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) -1 else error
            emitSignal("error", code)
        }

        override fun onResults(results: Bundle?) {
            if (!listening) {
                return
            }
            listening = false
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val best = matches?.firstOrNull() ?: ""
            emitSignal("listening_completed", best)
        }

        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    companion object {
        private const val PERMISSION_REQUEST = 4401
    }
}
