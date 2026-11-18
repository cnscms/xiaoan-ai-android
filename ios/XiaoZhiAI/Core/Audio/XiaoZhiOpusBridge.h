#ifndef XIAO_ZHI_OPUS_BRIDGE_H
#define XIAO_ZHI_OPUS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct XZOpusEncoder XZOpusEncoder;
typedef struct XZOpusDecoder XZOpusDecoder;

XZOpusEncoder *xz_opus_encoder_create(int32_t sample_rate, int32_t channels);
int32_t xz_opus_encoder_configure(
    XZOpusEncoder *encoder,
    int32_t bitrate,
    int32_t complexity
);
int32_t xz_opus_encode(
    XZOpusEncoder *encoder,
    const int16_t *pcm,
    int32_t frame_size,
    uint8_t *output,
    int32_t output_capacity
);
void xz_opus_encoder_destroy(XZOpusEncoder *encoder);

XZOpusDecoder *xz_opus_decoder_create(int32_t sample_rate, int32_t channels);
int32_t xz_opus_decode(
    XZOpusDecoder *decoder,
    const uint8_t *packet,
    int32_t packet_size,
    int16_t *output,
    int32_t output_capacity
);
void xz_opus_decoder_destroy(XZOpusDecoder *decoder);

const char *xz_opus_error_string(int32_t error);

#ifdef __cplusplus
}
#endif

#endif

