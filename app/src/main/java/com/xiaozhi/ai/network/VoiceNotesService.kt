package com.xiaozhi.ai.network

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.xiaozhi.ai.data.XiaozhiConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

data class VoiceNoteBindingStatus(
    val deviceId: String,
    val bound: Boolean,
    val phone: String?
)

class VoiceNotesService {
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun checkBinding(config: XiaozhiConfig): Result<VoiceNoteBindingStatus> =
        withContext(Dispatchers.IO) {
            runCatching {
                val base = requireBase(config)
                val encodedDevice = URLEncoder.encode(
                    config.macAddress,
                    StandardCharsets.UTF_8.name()
                )
                val request = Request.Builder()
                    .url("$base/api/device-binding?deviceId=$encodedDevice")
                    .get()
                    .voiceNoteHeaders(config)
                    .build()
                execute(request)
            }
        }

    suspend fun bindPhone(
        config: XiaozhiConfig,
        phone: String
    ): Result<VoiceNoteBindingStatus> = withContext(Dispatchers.IO) {
        runCatching {
            val base = requireBase(config)
            val body = JsonObject().apply {
                addProperty("deviceId", config.macAddress)
                addProperty("phone", phone.trim())
            }.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$base/api/device-binding")
                .post(body)
                .voiceNoteHeaders(config)
                .build()
            val root = executeRaw(request)
            val binding = root.getAsJsonObject("binding")
            VoiceNoteBindingStatus(
                deviceId = binding.get("deviceId")?.asString.orEmpty(),
                bound = true,
                phone = binding.get("phone")?.asString
            )
        }
    }

    private fun execute(request: Request): VoiceNoteBindingStatus {
        val root = executeRaw(request)
        return VoiceNoteBindingStatus(
            deviceId = root.get("deviceId")?.asString.orEmpty(),
            bound = root.get("bound")?.asBoolean == true,
            phone = root.get("phone")?.takeUnless { it.isJsonNull }?.asString
        )
    }

    private fun executeRaw(request: Request): JsonObject {
        client.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val message = runCatching {
                    JsonParser.parseString(text).asJsonObject
                        .get("error")?.asString
                }.getOrNull()
                error(message ?: "VoiceNote HTTP ${response.code}")
            }
            return JsonParser.parseString(text).asJsonObject
        }
    }

    private fun Request.Builder.voiceNoteHeaders(
        config: XiaozhiConfig
    ): Request.Builder {
        val token = config.voiceNotesToken.orEmpty()
        if (token.isBlank()) {
            error("请先配置 VoiceNote Token")
        }
        return addHeader("X-Voice-Notes-Token", token)
            .addHeader("Accept", "application/json")
            .addHeader("Content-Type", "application/json")
    }

    private fun requireBase(config: XiaozhiConfig): String {
        val value = config.voiceNotesUrl.orEmpty().trim().trimEnd('/')
        require(value.startsWith("http://") || value.startsWith("https://")) {
            "VoiceNote 服务地址无效"
        }
        return value
    }
}
