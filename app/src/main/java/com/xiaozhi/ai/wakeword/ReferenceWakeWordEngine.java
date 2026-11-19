package com.xiaozhi.ai.wakeword;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.util.Log;

import com.k2fsa.sherpa.onnx.FeatureConfig;
import com.k2fsa.sherpa.onnx.KeywordSpotter;
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig;
import com.k2fsa.sherpa.onnx.KeywordSpotterResult;
import com.k2fsa.sherpa.onnx.OnlineModelConfig;
import com.k2fsa.sherpa.onnx.OnlineStream;
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * In-process wake-word engine matching the reference APK behavior.
 * It owns the microphone only while actively listening and releases it as soon
 * as conversation recording or playback begins.
 */
public final class ReferenceWakeWordEngine {
    private static final String TAG = "LocalWakeWord";
    public interface Listener {
        void onWake(String keyword);
        void onListeningChanged(boolean listening);
    }

    private static final String ASSET_DIR =
            "sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01";
    private static final String MODEL_DIR = "wakeword-local-2.0.1";
    private static final String MODEL_MARKER = ".ready-2.0.1";
    private static final String[] MODEL_FILES = {
            "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
            "decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
            "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
            "tokens.txt",
            "keywords.txt"
    };

    private final Context context;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile boolean running;
    private volatile boolean paused;
    private volatile boolean listening;
    private volatile AudioRecord recorder;
    private Thread thread;

    public ReferenceWakeWordEngine(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
    }

    public boolean isRunning() {
        return running;
    }

    public boolean isListening() {
        return listening;
    }

    public synchronized void start() {
        if (running) {
            paused = false;
            return;
        }
        running = true;
        paused = false;
        Log.i(TAG, "进程内 Sherpa-ONNX 唤醒引擎启动");
        thread = new Thread(this::loop, "xiaozhi-reference-wake");
        thread.setDaemon(true);
        thread.start();
    }

    public void setPaused(boolean value) {
        if (paused != value) {
            Log.i(TAG, value ? "本地唤醒暂停：对话占用麦克风" : "本地唤醒恢复监听");
        }
        paused = value;
    }

    public synchronized void stop() {
        running = false;
        paused = true;
        Log.i(TAG, "进程内唤醒引擎停止");
        closeRecorder();
        Thread current = thread;
        thread = null;
        if (current != null) {
            current.interrupt();
            try {
                current.join(800L);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }
        listening = false;
        listener.onListeningChanged(false);
    }

    private void loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO);
        KeywordSpotter spotter = null;
        OnlineStream stream = null;
        AudioRecord record = null;
        boolean recording = false;
        try {
            File modelDir = prepareModel();
            FeatureConfig feature = new FeatureConfig();
            feature.setSampleRate(16000);
            feature.setFeatureDim(80);
            feature.setDither(0.0f);
            OnlineTransducerModelConfig transducer =
                    new OnlineTransducerModelConfig();
            transducer.setEncoder(new File(modelDir, MODEL_FILES[0]).getAbsolutePath());
            transducer.setDecoder(new File(modelDir, MODEL_FILES[1]).getAbsolutePath());
            transducer.setJoiner(new File(modelDir, MODEL_FILES[2]).getAbsolutePath());
            OnlineModelConfig model = new OnlineModelConfig();
            model.setTransducer(transducer);
            model.setTokens(new File(modelDir, "tokens.txt").getAbsolutePath());
            model.setNumThreads(1);
            model.setDebug(false);
            model.setProvider("cpu");
            KeywordSpotterConfig config = new KeywordSpotterConfig();
            config.setFeatConfig(feature);
            config.setModelConfig(model);
            config.setKeywordsFile(
                    new File(modelDir, "keywords.txt").getAbsolutePath());
            config.setKeywordsScore(1.5f);
            config.setKeywordsThreshold(0.25f);
            config.setMaxActivePaths(0);
            config.setNumTrailingBlanks(1);
            spotter = new KeywordSpotter(null, config);
            stream = spotter.createStream("");
            short[] pcm = new short[1600];
            float[] samples = new float[pcm.length];

            while (running) {
                if (paused) {
                    if (recording) {
                        stopRecorder(record);
                        recording = false;
                        listening = false;
                        listener.onListeningChanged(false);
                    }
                    spotter.reset(stream);
                    Thread.sleep(100L);
                    continue;
                }
                if (!recording) {
                    if (record == null) {
                        record = openRecorder();
                    }
                    if (record == null) {
                        Thread.sleep(1000L);
                        continue;
                    }
                    try {
                        record.startRecording();
                        if (record.getRecordingState()
                                != AudioRecord.RECORDSTATE_RECORDING) {
                            throw new IllegalStateException("后台录音器未启动");
                        }
                    } catch (Throwable error) {
                        releaseRecorder(record);
                        record = null;
                        Thread.sleep(800L);
                        continue;
                    }
                    spotter.reset(stream);
                    recording = true;
                    listening = true;
                    Log.i(TAG, "AudioRecord 已启动：16kHz/单声道/本地 KWS");
                    listener.onListeningChanged(true);
                }
                int count = record.read(pcm, 0, pcm.length, AudioRecord.READ_BLOCKING);
                if (count <= 0) {
                    releaseRecorder(record);
                    record = null;
                    recording = false;
                    listening = false;
                    listener.onListeningChanged(false);
                    Thread.sleep(800L);
                    continue;
                }
                for (int i = 0; i < count; i++) {
                    samples[i] = pcm[i] / 32768.0f;
                }
                stream.acceptWaveform(samples, count);
                while (spotter.isReady(stream)) {
                    spotter.decode(stream);
                }
                KeywordSpotterResult result = spotter.getResult(stream);
                String keyword = result == null ? "" : result.getKeyword();
                if (keyword != null && !keyword.isEmpty()) {
                    Log.i(TAG, "唤醒词命中：" + keyword);
                    spotter.reset(stream);
                    paused = true;
                    if (recording) {
                        stopRecorder(record);
                        recording = false;
                    }
                    listening = false;
                    listener.onListeningChanged(false);
                    mainHandler.post(() -> listener.onWake(keyword));
                    Thread.sleep(1200L);
                }
            }
        } catch (Throwable error) {
            Log.e(TAG, "唤醒引擎异常: " + error.getClass().getSimpleName()
                    + " " + error.getMessage());
            listening = false;
            listener.onListeningChanged(false);
        } finally {
            if (stream != null) {
                try {
                    stream.release();
                } catch (Throwable ignored) {
                }
            }
            if (spotter != null) {
                try {
                    spotter.release();
                } catch (Throwable ignored) {
                }
            }
            if (record != null) {
                releaseRecorder(record);
            }
            listening = false;
            listener.onListeningChanged(false);
            if (running) {
                mainHandler.postDelayed(() -> {
                    synchronized (ReferenceWakeWordEngine.this) {
                        if (running) {
                            thread = null;
                            stop();
                            start();
                        }
                    }
                }, 1500L);
            }
        }
    }

    private static void stopRecorder(AudioRecord record) {
        if (record == null) {
            return;
        }
        try {
            record.stop();
        } catch (Throwable ignored) {
        }
    }

    private AudioRecord openRecorder() {
        int minBuffer = AudioRecord.getMinBufferSize(
                16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        AudioRecord record = null;
        try {
            record = new AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    16000,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    Math.max(minBuffer, 6400));
            if (record.getState() == AudioRecord.STATE_INITIALIZED) {
                recorder = record;
                return record;
            }
        } catch (Throwable ignored) {
        }
        if (record != null) {
            releaseRecorder(record);
        }
        return null;
    }

    private void closeRecorder() {
        AudioRecord current = recorder;
        recorder = null;
        if (current != null) {
            releaseRecorder(current);
        }
    }

    private static void releaseRecorder(AudioRecord record) {
        try {
            record.stop();
        } catch (Throwable ignored) {
        }
        try {
            record.release();
        } catch (Throwable ignored) {
        }
    }

    private File prepareModel() throws Exception {
        File target = new File(context.getFilesDir(), MODEL_DIR);
        if (!target.isDirectory() && !target.mkdirs()) {
            throw new IllegalStateException("无法创建唤醒模型目录");
        }
        File marker = new File(target, MODEL_MARKER);
        boolean complete = marker.isFile() && marker.length() > 0;
        if (complete) {
            for (String name : MODEL_FILES) {
                File file = new File(target, name);
                if (!file.isFile() || file.length() == 0) {
                    complete = false;
                    break;
                }
            }
        }
        if (complete) {
            return target;
        }
        if (marker.exists() && !marker.delete()) {
            throw new IllegalStateException("无法更新唤醒模型标记");
        }
        for (String name : MODEL_FILES) {
            File output = new File(target, name);
            try (InputStream input =
                         context.getAssets().open(ASSET_DIR + "/" + name);
                 FileOutputStream file = new FileOutputStream(output)) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) >= 0) {
                    file.write(buffer, 0, count);
                }
                file.getFD().sync();
            }
        }
        try (FileOutputStream markerStream = new FileOutputStream(marker)) {
            markerStream.write("2.0.1".getBytes("UTF-8"));
            markerStream.getFD().sync();
        }
        Log.i(TAG, "本地唤醒模型准备完成：" + MODEL_DIR);
        return target;
    }

}
