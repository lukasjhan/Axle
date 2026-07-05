package com.hopae.eudi.demo.adapters

import com.hopae.eudi.demo.LogStore
import com.hopae.eudi.wallet.spi.HttpMethod
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** [HttpTransport] backed by OkHttp — logs every call to [LogStore] and honours the per-request redirect policy. */
class OkHttpTransport(private val base: OkHttpClient = OkHttpClient()) : HttpTransport {

    override suspend fun execute(request: HttpRequest): HttpResponse = withContext(Dispatchers.IO) {
        val client = if (request.followRedirects) base
        else base.newBuilder().followRedirects(false).followSslRedirects(false).build()

        val builder = Request.Builder().url(request.url)
        request.headers.forEach { builder.addHeader(it.first, it.second) }
        val body = request.body?.toRequestBody()
        when (request.method) {
            HttpMethod.GET -> builder.get()
            HttpMethod.POST -> builder.post(body ?: ByteArray(0).toRequestBody())
            HttpMethod.PUT -> builder.put(body ?: ByteArray(0).toRequestBody())
            HttpMethod.PATCH -> builder.patch(body ?: ByteArray(0).toRequestBody())
            HttpMethod.DELETE -> if (body != null) builder.delete(body) else builder.delete()
        }

        LogStore.log("HTTP → ${request.method} ${request.url}")
        val t0 = System.currentTimeMillis()
        try {
            client.newCall(builder.build()).execute().use { response ->
                val bytes = response.body?.bytes() ?: ByteArray(0)
                LogStore.log("HTTP ← ${response.code} ${request.url}  (${System.currentTimeMillis() - t0}ms, ${bytes.size}B)")
                HttpResponse(response.code, response.headers.map { it.first to it.second }, bytes)
            }
        } catch (e: Exception) {
            LogStore.log("HTTP ✗ ${request.url}  ${e.javaClass.simpleName}: ${e.message}")
            throw e
        }
    }
}
