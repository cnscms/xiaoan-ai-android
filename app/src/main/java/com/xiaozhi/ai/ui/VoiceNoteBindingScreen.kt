package com.xiaozhi.ai.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaozhi.ai.data.XiaozhiConfig
import com.xiaozhi.ai.network.VoiceNoteBindingStatus
import com.xiaozhi.ai.network.VoiceNotesService
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceNoteBindingScreen(
    config: XiaozhiConfig,
    onConfigChange: (XiaozhiConfig) -> Unit,
    onBack: () -> Unit
) {
    var editedConfig by remember {
        mutableStateOf(
            config.copy(
                voiceNotesUrl = config.voiceNotesUrl
                    ?.takeIf { it.isNotBlank() }
                    ?: XiaozhiConfig.DEFAULT_VOICE_NOTES_URL
            )
        )
    }
    var phone by remember { mutableStateOf(config.voiceNotesPhone.orEmpty()) }
    var binding by remember { mutableStateOf<VoiceNoteBindingStatus?>(null) }
    var statusText by remember { mutableStateOf("") }
    var errorText by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val service = remember { VoiceNotesService() }

    fun persist(bound: Boolean? = null) {
        val updated = editedConfig.copy(
            voiceNotesPhone = phone.trim(),
            voiceNotesBound = bound ?: binding?.bound ?: false
        )
        editedConfig = updated
        onConfigChange(updated)
    }

    fun checkBinding() {
        loading = true
        errorText = null
        scope.launch {
            service.checkBinding(editedConfig)
                .onSuccess {
                    binding = it
                    if (it.bound) {
                        statusText = "已绑定 ${it.phone.orEmpty()}"
                        persist(true)
                    } else {
                        statusText = "当前设备尚未绑定手机号"
                        persist(false)
                    }
                }
                .onFailure {
                    errorText = it.message ?: "检查绑定失败"
                }
            loading = false
        }
    }

    fun bindPhone() {
        loading = true
        errorText = null
        scope.launch {
            service.bindPhone(editedConfig, phone)
                .onSuccess {
                    binding = it
                    statusText = "绑定成功 ${it.phone.orEmpty()}"
                    persist(true)
                }
                .onFailure {
                    errorText = it.message ?: "手机号绑定失败"
                }
            loading = false
        }
    }

    LaunchedEffect(Unit) {
        if (editedConfig.voiceNotesToken.orEmpty().isNotBlank()) {
            checkBinding()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AethericColors.Background)
    ) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            containerColor = Color.Transparent,
            topBar = {
                CenterAlignedTopAppBar(
                    title = {
                        Text(
                            "VoiceNote 手机号绑定",
                            fontSize = 19.sp,
                            fontWeight = FontWeight.Bold,
                            color = AethericColors.OnSurface
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(
                                Icons.Default.ArrowBack,
                                contentDescription = "返回",
                                tint = AethericColors.OnSurface
                            )
                        }
                    },
                    actions = {
                        TextButton(onClick = { persist() }) {
                            Text(
                                "保存",
                                color = AethericColors.Primary,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = Color.Transparent
                    ),
                    modifier = Modifier.statusBarsPadding()
                )
            }
        ) { padding ->
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(horizontal = 22.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                item {
                    SettingsSection(title = "VoiceNote 服务") {
                        SettingsInput(
                            label = "服务器地址",
                            value = editedConfig.voiceNotesUrl.orEmpty(),
                            onValueChange = {
                                editedConfig = editedConfig.copy(voiceNotesUrl = it)
                            },
                            placeholder = XiaozhiConfig.DEFAULT_VOICE_NOTES_URL
                        )
                        Spacer(Modifier.height(14.dp))
                        SettingsInput(
                            label = "VoiceNote Token",
                            value = editedConfig.voiceNotesToken.orEmpty(),
                            onValueChange = {
                                editedConfig = editedConfig.copy(voiceNotesToken = it)
                            },
                            placeholder = "X-Voice-Notes-Token"
                        )
                        Spacer(Modifier.height(14.dp))
                        SettingsInput(
                            label = "Device-Id",
                            value = editedConfig.macAddress,
                            onValueChange = {
                                editedConfig = editedConfig.copy(macAddress = it)
                            },
                            placeholder = "设备 MAC / Device-Id"
                        )
                    }
                }

                item {
                    SettingsSection(title = "手机号绑定") {
                        Text(
                            "语音记事和提醒按设备 ID 归属。绑定手机号后，服务端会回填这台设备已有的记事和提醒。",
                            color = AethericColors.OnSurfaceVariant,
                            fontSize = 13.sp,
                            lineHeight = 19.sp
                        )
                        Spacer(Modifier.height(14.dp))
                        SettingsInput(
                            label = "手机号",
                            value = phone,
                            onValueChange = {
                                phone = it.filter(Char::isDigit).take(11)
                                errorText = null
                            },
                            placeholder = "11 位中国大陆手机号"
                        )
                        Spacer(Modifier.height(16.dp))
                        if (loading) {
                            CircularProgressIndicator(
                                modifier = Modifier.height(24.dp),
                                color = AethericColors.Primary,
                                strokeWidth = 2.dp
                            )
                        } else {
                            Button(
                                onClick = ::bindPhone,
                                enabled = phone.length == 11 &&
                                    editedConfig.voiceNotesToken.orEmpty().isNotBlank(),
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = AethericColors.Primary
                                )
                            ) {
                                Icon(Icons.Default.Link, contentDescription = null)
                                Spacer(Modifier.padding(horizontal = 4.dp))
                                Text("绑定手机号")
                            }
                            Spacer(Modifier.height(8.dp))
                            TextButton(
                                onClick = ::checkBinding,
                                enabled = editedConfig.voiceNotesToken.orEmpty().isNotBlank(),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                if (binding?.bound == true) {
                                    Icon(
                                        Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = Color(0xFF18864B)
                                    )
                                    Spacer(Modifier.padding(horizontal = 3.dp))
                                }
                                Text("检查当前绑定状态")
                            }
                        }
                        if (statusText.isNotBlank()) {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                statusText,
                                color = if (binding?.bound == true) {
                                    Color(0xFF18864B)
                                } else {
                                    AethericColors.OnSurfaceVariant
                                },
                                fontSize = 13.sp
                            )
                        }
                        errorText?.let {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                it,
                                color = MaterialTheme.colorScheme.error,
                                fontSize = 13.sp
                            )
                        }
                    }
                }
            }
        }
    }
}
