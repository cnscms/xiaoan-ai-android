#include "XiaoZhiOpusBridge.h"

#include <stdlib.h>
#include <opus/opus.h>

struct XZOpusEncoder {
    OpusEncoder *value;
};

struct XZOpusDecoder {
    OpusDecoder *value;
};

XZOpusEncoder *xz_opus_encoder_create(int32_t sample_rate, int32_t channels) {
    int error = OPUS_OK;
    OpusEncoder *value = opus_encoder_create(
        sample_rate,
        channels,
        OPUS_APPLICATION_VOIP,
        &error
    );
    if (error != OPUS_OK || value == NULL) {
        return NULL;
    }
    XZOpusEncoder *encoder = calloc(1, sizeof(XZOpusEncoder));
    if (encoder == NULL) {
        opus_encoder_destroy(value);
        return NULL;
    }
    encoder->value = value;
    return encoder;
}

int32_t xz_opus_encoder_configure(
    XZOpusEncoder *encoder,
    int32_t bitrate,
    int32_t complexity
) {
    if (encoder == NULL) {
        return OPUS_BAD_ARG;
    }
    int result = opus_encoder_ctl(encoder->value, OPUS_SET_BITRATE(bitrate));
    if (result != OPUS_OK) {
        return result;
    }
    result = opus_encoder_ctl(encoder->value, OPUS_SET_COMPLEXITY(complexity));
    if (result != OPUS_OK) {
        return result;
    }
    result = opus_encoder_ctl(encoder->value, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    if (result != OPUS_OK) {
        return result;
    }
    return opus_encoder_ctl(encoder->value, OPUS_SET_INBAND_FEC(1));
}

int32_t xz_opus_encode(
    XZOpusEncoder *encoder,
    const int16_t *pcm,
    int32_t frame_size,
    uint8_t *output,
    int32_t output_capacity
) {
    if (encoder == NULL || pcm == NULL || output == NULL) {
        return OPUS_BAD_ARG;
    }
    return opus_encode(
        encoder->value,
        pcm,
        frame_size,
        output,
        output_capacity
    );
}

void xz_opus_encoder_destroy(XZOpusEncoder *encoder) {
    if (encoder == NULL) {
        return;
    }
    opus_encoder_destroy(encoder->value);
    free(encoder);
}

XZOpusDecoder *xz_opus_decoder_create(int32_t sample_rate, int32_t channels) {
    int error = OPUS_OK;
    OpusDecoder *value = opus_decoder_create(sample_rate, channels, &error);
    if (error != OPUS_OK || value == NULL) {
        return NULL;
    }
    XZOpusDecoder *decoder = calloc(1, sizeof(XZOpusDecoder));
    if (decoder == NULL) {
        opus_decoder_destroy(value);
        return NULL;
    }
    decoder->value = value;
    return decoder;
}

int32_t xz_opus_decode(
    XZOpusDecoder *decoder,
    const uint8_t *packet,
    int32_t packet_size,
    int16_t *output,
    int32_t output_capacity
) {
    if (decoder == NULL || output == NULL || output_capacity <= 0) {
        return OPUS_BAD_ARG;
    }
    return opus_decode(
        decoder->value,
        packet,
        packet_size,
        output,
        output_capacity,
        0
    );
}

void xz_opus_decoder_destroy(XZOpusDecoder *decoder) {
    if (decoder == NULL) {
        return;
    }
    opus_decoder_destroy(decoder->value);
    free(decoder);
}

const char *xz_opus_error_string(int32_t error) {
    return opus_strerror(error);
}
