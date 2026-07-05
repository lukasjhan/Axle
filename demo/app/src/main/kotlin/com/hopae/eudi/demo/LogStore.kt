package com.hopae.eudi.demo

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** In-app debug log sink — mirrors to logcat (`EudiDemo`) and to a StateFlow the Debug Log screen renders. */
object LogStore {
    private const val TAG = "EudiDemo"
    private const val MAX = 1000
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    private val _lines = MutableStateFlow<List<String>>(emptyList())
    val lines: StateFlow<List<String>> = _lines

    fun log(message: String) {
        Log.d(TAG, message)
        val line = "${fmt.format(Date())}  $message"
        _lines.update { (it + line).takeLast(MAX) }
    }

    fun clear() { _lines.value = emptyList() }

    fun asText(): String = _lines.value.joinToString("\n")
}
