package com.xiaozhi.ai.data

/**
 * 小安配置数据类
 */
data class XiaozhiConfig(
    val id: String,
    val name: String,
    val otaUrl: String,
    val websocketUrl: String = "",
    val macAddress: String,
    val uuid: String,
    val token: String,
    val voiceNotesUrl: String? = XiaozhiConfig.DEFAULT_VOICE_NOTES_URL,
    val voiceNotesToken: String? = "",
    val voiceNotesPhone: String? = "",
    val voiceNotesBound: Boolean = false,
    val mcpEnabled: Boolean = false,
    val mcpServers: List<McpServer> = emptyList()
) {
    companion object {
        const val DEFAULT_VOICE_NOTES_URL = "http://192.168.0.20:19090"

        /**
         * 创建默认配置
         */
        fun createDefault(): XiaozhiConfig {
            return XiaozhiConfig(
                id = "default",
                name = "Android",
                otaUrl = "",
                websocketUrl = "",
                macAddress = "",
                uuid = generateRandomUuid(),
                token = "test-token",
                voiceNotesUrl = DEFAULT_VOICE_NOTES_URL,
                voiceNotesToken = "",
                voiceNotesPhone = "",
                voiceNotesBound = false,
                mcpEnabled = false,
                mcpServers = listOf(
                    McpServer("示例MCP服务器", "ws://example.com/mcp", false)
                )
            )
        }
        
        /**
         * 生成随机MAC地址
         */
        private fun generateRandomMacAddress(): String {
            val random = java.util.Random()
            val mac = ByteArray(6)
            random.nextBytes(mac)
            return mac.joinToString(":") { "%02X".format(it) }
        }
        
        /**
         * 生成随机UUID
         */
        fun generateRandomUuid(): String {
            return java.util.UUID.randomUUID().toString()
        }
    }
}

/**
 * MCP服务器配置
 */
data class McpServer(
    val name: String,
    val url: String,
    val enabled: Boolean = true
)
