# Comprehensive Plan to Improve A311D2(T7) Wave521 Encoder Driver

## Executive Summary

The A311D2 SOC's Wave521 hardware video encoder has extensive capabilities, but many features are not exposed through the current software stack. This document identifies available hardware features and provides a detailed plan to expose them through improved driver and GStreamer plugin implementation.

---

## Hardware Feature Support Status

### Supported Features (Present but Often Disabled)

#### 1. 10-bit Color Depth Encoding
**Status**: Supported in hardware, disabled by default

**Evidence**:
- Hardcoded to 8-bit in current driver:
```c
param->internalBitDepth = 8;
```

- Hardware supports 10-bit formats:
```c
FORMAT_420_P10_16BIT_MSB = 5,
FORMAT_420_P10_16BIT_LSB,
FORMAT_420_P10_32BIT_MSB,
FORMAT_420_P10_32BIT_LSB,
```

- Profile selection based on bit depth:
```c
if (param->internalBitDepth == 10) {
    pEncOP->outputFormat = FORMAT_420_P10_16BIT_MSB;
    if (pEncOP->bitstreamFormat == STD_HEVC) {
        param->profile = HEVC_PROFILE_MAIN10;
    } else {
        param->profile = AVC_PROFILE_HIGH10;
    }
}
```

**What's Missing**:
- API to set internalBitDepth
- GStreamer plugin doesn't support 10-bit input formats (P010)
- V4L2 driver doesn't expose 10-bit formats

**Required Improvements**:
1. Add internalBitDepth parameter to vl_encode_info_t structure
2. Modify encoder to use configurable bit depth instead of hardcoded 8
3. Add P010 format support to GStreamer plugin sink caps
4. Update VDIN V4L2 driver to advertise 10-bit output formats

---

#### 2. Lossless Encoding (Quantization/Transform Disabled)
**Status**: Supported in hardware, disabled by default

**Evidence**:
- Hardware parameter exists:
```c
int losslessEnable;
```

- Hardware register writes lossless flag
- Lossless mode disables incompatible features:
```c
// Lossless cannot be used with:
// - Rate Control
// - Noise Reduction
// - Background Detection
// - ROI
// - Requires: IntraTransSkip enabled
```

- Currently disabled in wrapper:
```c
param->losslessEnable = 0;
```

**What's Missing**:
- API to enable lossless encoding
- GStreamer property to enable lossless mode
- Documentation on lossless encoding requirements

**Required Improvements**:
1. Add losslessEnable parameter to vl_encode_info_t structure
2. Modify encoder to accept lossless mode from configuration
3. Add GStreamer property for lossless encoding
4. Ensure proper validation when lossless is enabled

---

#### 3. B Frame Encoding
**Status**: Supported in hardware, NOT enabled by default

**Evidence**:
- GOP mode with B frames exists:
```c
else if (InitParam->GopPreset == GOP_IBBBP) {
    param->gopPresetIdx = PRESET_IDX_IBBBP;
}
```

- Frame type enumeration includes B:
```c
FRAME_TYPE_B,
```

- B frame QP parameters defined:
```c
int initQP_B;
int maxQP_B;
int minQP_B;
```

- GOP presets defined:
```c
PRESET_IDX_IBBBP = 5,
```

**Default Behavior**:
```c
if (InitParam->GopPreset == GOP_OPT_NONE) {
   if (InitParam->idr_period == 1)
      param->gopPresetIdx = PRESET_IDX_ALL_I;
   else
      param->gopPresetIdx = PRESET_IDX_IPP;
}
```

**What's Missing**:
- GStreamer plugin only sets GOP size, not GOP pattern
- No API to select GOP preset (IP, IBBBP, etc.)
- Default is IP-only (no B frames)

**Required Improvements**:
1. Add gopPattern parameter to vl_encode_info_t structure
2. Add GStreamer property to select GOP pattern
3. Consider enabling B frames by default for better compression efficiency

---

## Missing Features

### 1. V4L2 Encoder Driver
**Status**: Not present

**Current State**:
- Encoder is accessed only through userspace multienc library
- No V4L2 M2M encoder driver in kernel
- GStreamer plugin uses direct API calls to multienc library

**Impact**:
- Cannot use standard V4L2 encoder applications
- Cannot use ffmpeg with V4L2 backend
- Limited to Amlogic-specific GStreamer plugins

**Required Improvement**:
- Implement V4L2 M2M encoder driver that wraps Wave521 hardware
- Expose encoder capabilities through standard V4L2 API

---

### 2. Missing HEVC Profiles
**Status**: Only Main and Main10 supported

**Supported Profiles**:
```c
#define HEVC_PROFILE_MAIN                   1
#define HEVC_PROFILE_MAIN10                 2
#define HEVC_PROFILE_STILLPICTURE           3
```

**Missing Profiles**:
- HEVC_PROFILE_MAIN_REXT (Range Extension)
- HEVC_PROFILE_MAIN_4:4:4
- HEVC_PROFILE_MAIN_4:4:4_10

**Impact**:
- Cannot use 4:4:4 chroma subsampling
- Limited to 4:2:0 chroma

---

### 3. Limited GOP Pattern Exposure
**Status**: Mostly fixed in the current development branch; full preset exposure is now wired through the userspace stack

**Available GOP Presets**:
- PRESET_IDX_CUSTOM_GOP (User defined)
- PRESET_IDX_ALL_I (All Intra)
- PRESET_IDX_IPP (Consecutive P)
- PRESET_IDX_IBBB (Consecutive B)
- PRESET_IDX_IBPBP (I-B-P-B-P)
- PRESET_IDX_IBBBP (I-B-B-B-P)
- PRESET_IDX_IPPPP (Consecutive P, larger GOP)
- PRESET_IDX_IBBBB (Consecutive B)
- PRESET_IDX_RA_IB (Random Access)
- PRESET_IDX_IPP_SINGLE (Single reference)

**Currently Accessible in the updated stack**:
- `IPP`
- `IBBBP`
- `IBPBP`
- `IBBB`
- `ALL_I`
- `IPPPP`
- `IBBBB`
- `RA_IB`
- `IPP_SINGLE`

**Implementation notes**:
- `multimedia/gst-plugin-venc/multienc-wave521/gstamlvenc_multienc.c` now exposes
  `gop-pattern=0..8`
- `hardware/aml-5.4/amlogic/libencoder/multiEnc/amvenc_lib/AML_MultiEncoder.c`
  maps the extended pattern set to Wave5 preset indices
- `hardware/aml-5.4/amlogic/libencoder/multiEnc/amvenc_lib/libvpmulti_codec.c`
  now treats the new low-delay presets consistently in H.264 SPS/VUI handling

**Runtime note for RA_IB**:
- `RA_IB` required deeper buffering than the original stack provided
- `multimedia/gst-plugin-vfmcap/gst_streambox_src.h`: Path-A output pool increased
  from 6 to 12 buffers
- `hardware/aml-5.4/amlogic/libencoder/multiEnc/amvenc_lib/AML_MultiEncoder.c`:
  source slot count increased from `minSrcFrameCount + 2` to
  `minSrcFrameCount + COMMAND_QUEUE_DEPTH`

**Verification summary**:
- All presets above now run successfully with HEVC on target
- `IBBBP`, `IBPBP`, `IBBB`, `IBBBB`, and `RA_IB` produce real B frames
- `gop=30` and `gop=60` were verified

---

### 4. Missing Input Format Support in GStreamer Plugin
**Status**: Only 8-bit formats supported

**Current Sink Caps**:
```c
g_value_set_string (&fmt, "NV12");
gst_value_list_append_value (&fmts, &fmt);
g_value_set_string (&fmt, "NV21");
gst_value_list_append_value (&fmts, &fmt);
g_value_set_string (&fmt, "I420");
gst_value_list_append_value (&fmts, &fmt);
g_value_set_string (&fmt, "YV12");
gst_value_list_append_value (&fmts, &fmt);
g_value_set_string (&fmt, "RGB");
gst_value_list_append_value (&fmts, &fmt);
g_value_set_string (&fmt, "BGR");
gst_value_list_append_value (&fmts, &fmt);
```

**Missing Formats**:
- P010 (10-bit NV12 equivalent)
- P210 (10-bit NV21 equivalent)
- Other 10-bit planar formats

---

### 5. HDR Metadata Support
**Status**: VDIN driver supports HDR10, but not exposed to encoder

**Evidence**:
- VDIN HDR handling exists
- HDR10 detection in VDIN driver

**What's Missing**:
- HDR metadata not passed from VDIN to encoder
- No API to configure HDR encoding parameters
- No HDR static/dynamic metadata

---

### 6. ROI Control Not Fully Exposed
**Status**: Partially implemented

**Evidence**:
- ROI functionality exists in hardware
- GStreamer has ROI properties

**Limitations**:
- Complex to configure (requires multiple properties)
- Not compatible with lossless encoding
- No documentation on optimal ROI usage

---

## Feature Summary Table

| Feature | Hardware Support | Driver/API Support | GStreamer Support | Default Enabled |
|----------|------------------|-------------------|-------------------|-----------------|
| 8-bit Encoding | Yes | Yes | Yes | Yes |
| 10-bit Encoding | Yes | No | No | No |
| Lossless (no quant/transform) | Yes | No | No | No |
| B Frames | Yes | Yes | No | No |
| I Frames Only | Yes | Yes | Yes | No |
| HEVC Main Profile | Yes | Yes | Yes | Yes |
| HEVC Main10 Profile | Yes | No | No | No |
| HEVC Main 4:4:4 | No | No | No | N/A |
| HEVC REXT Profile | No | No | No | N/A |
| V4L2 Encoder Driver | Yes | No | N/A | N/A |
| HDR Metadata | Yes (capture) | No | No | N/A |

---

## Recommended Implementation Priority

### High Priority (Significant Impact)
1. Enable 10-bit encoding
   - Add internalBitDepth parameter to API
   - Update GStreamer plugin for P010 format
   - Test with HDR10 loopback

2. Enable B frames by default or expose GOP pattern
   - Add gop-pattern property to GStreamer
   - Default to IBBBP for better compression

3. Implement V4L2 encoder driver
   - Enables standard Linux applications
   - Improves ecosystem compatibility

### Medium Priority
4. Expose lossless encoding option
   - Add lossless property
   - Document requirements

5. Improve ROI control
   - Simplify API
   - Add examples/documentation

### Low Priority
6. HDR metadata support
   - Pass HDR info from VDIN to encoder
   - Add HDR10/HDR10+ configuration

---

## Code Locations Reference

### Hardware/Library Layer
- Main encoder implementation: hardware/aml-5.4/amlogic/libencoder/multiEnc/amvenc_lib/AML_MultiEncoder.c
- API header: hardware/aml-5.4/amlogic/libencoder/multiEnc/amvenc_lib/include/vp_multi_codec_1_0.h
- Low-level driver: hardware/aml-5.4/amlogic/libencoder/multiEnc/vpuapi/enc_driver.c
- VPU API: hardware/aml-5.4/amlogic/libencoder/multiEnc/vpuapi/include/vpuapi.h

### GStreamer Plugin
- Multienc plugin: multimedia/gst-plugin-venc/multienc-wave521/gstamlvenc_multienc.c
- Multienc header: multimedia/gst-plugin-venc/multienc-wave521/gstamlvenc_multienc.h

### Kernel Drivers
- VDIN (capture): kernel/aml-5.15/common_drivers/drivers/media/vin/tvin/vdin/
- VPU driver: kernel/aml-5.15/common_drivers/drivers/media/common/vpu/

---

## Detailed Feature Gap Analysis

### Rate Control Features

#### Current Implementation
- Basic rate control enable/disable via rcEnable flag
- Bitrate control
- Initial QP setting

#### Missing Features
1. **VBR/CBR Mode Selection**
   - CBR mode enables filler data for strict rate control
   - VBR allows variable bitrate with quality targets
   - Currently not exposed to applications

2. **Per-Frame-Type QP Control**
   - Separate QP ranges for I, P, B frames
   - Current implementation has limited QP control
   - Better quality control with per-frame-type settings

3. **CU-Level Rate Control**
   - Hardware supports CU-level rate control
   - Allows more precise bitrate distribution
   - Better visual quality

4. **HVS QP Enhancement**
   - Human Visual System QP adjustment
   - Improves subjective quality
   - Configurable scaling factor

5. **VBV Buffer Control**
   - Configurable VBV buffer size (10-3000ms)
   - Better bitrate compliance
   - Important for streaming applications

### Advanced Encoding Features

#### 1. Noise Reduction
**Status**: Supported but not exposed

**Hardware Capabilities**:
- Separate Y/Cb/Cr noise reduction
- Intra/inter frame weights
- Noise level estimation or manual configuration

**Missing**:
- API to enable/configure noise reduction
- GStreamer properties for NR parameters

#### 2. Background Detection
**Status**: Supported but not exposed

**Hardware Capabilities**:
- Background area detection
- Separate QP for background/foreground
- Configurable thresholds

**Missing**:
- API to enable background detection
- GStreamer properties for BG detection

#### 3. Custom GOP Structures
**Status**: Partially supported

**Current Support**:
- Several preset GOP patterns
- Limited custom GOP support

**Missing**:
- Full custom GOP definition
- Flexible reference picture selection
- Temporal layer support

#### 4. Custom Lambda Table
**Status**: Supported but not exposed

**Hardware Capabilities**:
- Custom RD cost tables
- PU-size specific rate adjustments
- Advanced mode decision control

#### 5. Custom Mode Decision
**Status**: Supported but not exposed

**Hardware Capabilities**:
- Custom intra/inter cost adjustments
- Transform skip control
- SAO and deblocking fine-tuning

---

## Phase 1: Critical Features

### 1.1 Enable 10-bit Encoding

#### API Changes
Add to vp_multi_codec_1_0.h:
```c
typedef struct vl_encode_info {
    // ... existing fields ...
    int internal_bit_depth;
    int output_bit_depth;
} // STREAMBOX_IMPROVE
```

#### Driver Changes
Modify AML_MultiEncoder.c:
```c
param->internalBitDepth = InitParam->internal_bit_depth;

if (param->internalBitDepth == 10) {
    pEncOP->outputFormat = FORMAT_420_P10_16BIT_MSB;
    if (pEncOP->bitstreamFormat == STD_HEVC) {
        param->profile = HEVC_PROFILE_MAIN10;
    } else {
        param->profile = AVC_PROFILE_HIGH10;
    }
}
```

#### GStreamer Plugin
Add to gstamlvenc_multienc.c:
```c
g_value_set_string (&fmt, "P010");
gst_value_list_append_value (&fmts, &fmt);
```

Add property:
```c
PROP_INTERNAL_BIT_DEPTH = 8

g_object_class_install_property (gobject_class, PROP_INTERNAL_BIT_DEPTH,
    g_param_spec_int ("internal-bit-depth", "Internal Bit Depth",
        "Encoder internal bit depth (8 or 10)",
        8, 10, 8, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
```

---

### 1.2 Enable Lossless Encoding

#### API Changes
Add to vp_multi_codec_1_0.h:
```c
typedef struct vl_encode_info {
    // ... existing fields ...
    bool lossless_enable;
} // STREAMBOX_IMPROVE
```

#### Driver Changes
Modify AML_MultiEncoder.c:
```c
param->losslessEnable = InitParam->lossless_enable;

if (param->losslessEnable) {
    param->rcEnable = 0;
    param->nrYEnable = 0;
    param->nrCbEnable = 0;
    param->nrCrEnable = 0;
    param->roiEnable = 0;
    param->bgDetectEnable = 0;
    param->skipIntraTrans = 1;
}
```

#### GStreamer Plugin
Add property:
```c
PROP_LOSSLESS_ENABLE = FALSE

g_object_class_install_property (gobject_class, PROP_LOSSLESS_ENABLE,
    g_param_spec_boolean ("lossless-enable", "Lossless Encoding",
        "Enable lossless encoding (disables rate control, NR, ROI)",
        FALSE, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
```

---

### 1.3 Enable B Frames with GOP Pattern Selection

#### API Changes
Add to vp_multi_codec_1_0.h:
```c
typedef enum {
    GOP_PATTERN_IP = 0,
    GOP_PATTERN_IBBBP = 1,
    GOP_PATTERN_IBPBP = 2,
    GOP_PATTERN_IBBB = 3,
    GOP_PATTERN_ALL_I = 4,
    GOP_PATTERN_CUSTOM = 99
} gop_pattern_t; // STREAMBOX_IMPROVE

typedef struct vl_encode_info {
    // ... existing fields ...
    gop_pattern_t gop_pattern;
} // STREAMBOX_IMPROVE
```

#### Driver Changes
Modify AML_MultiEncoder.c:
```c
switch (InitParam->gop_pattern) {
    case GOP_PATTERN_IP:
        param->gopPresetIdx = PRESET_IDX_IPP;
        break;
    case GOP_PATTERN_IBBBP:
        param->gopPresetIdx = PRESET_IDX_IBBBP;
        break;
    case GOP_PATTERN_IBPBP:
        param->gopPresetIdx = PRESET_IDX_IBPBP;
        break;
    case GOP_PATTERN_ALL_I:
        param->gopPresetIdx = PRESET_IDX_ALL_I;
        break;
    default:
        param->gopPresetIdx = PRESET_IDX_IPP;
        break;
}
```

#### GStreamer Plugin
Add property:
```c
PROP_GOP_PATTERN = 0

g_object_class_install_property (gobject_class, PROP_GOP_PATTERN,
    g_param_spec_enum ("gop-pattern", "GOP Pattern",
        "GOP structure pattern (0=IP, 1=IBBBP, 2=IBPBP, 3=ALL_I)",
        0, 4, 0, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
```

---

### 1.4 Implement VBR/CBR Rate Control Selection

#### API Changes
Add to vp_multi_codec_1_0.h:
```c
typedef enum {
    RC_MODE_VBR = 0,
    RC_MODE_CBR = 1,
    RC_MODE_CQP = 2
} rc_mode_t; // STREAMBOX_IMPROVE

typedef struct vl_encode_info {
    // ... existing fields ...
    rc_mode_t rc_mode;
} // STREAMBOX_IMPROVE
```

#### Driver Changes
Modify AML_MultiEncoder.c:
```c
pEncOP->rcEnable = (InitParam->rc_mode != RC_MODE_CQP);

if (InitParam->rc_mode == RC_MODE_CBR) {
    pEncOP->enable_filler_data = TRUE;
}
```

#### GStreamer Plugin
Add property:
```c
PROP_RC_MODE = 0

g_object_class_install_property (gobject_class, PROP_RC_MODE,
    g_param_spec_enum ("rc-mode", "Rate Control Mode",
        "Rate control mode (0=VBR, 1=CBR, 2=CQP)",
        0, 2, 0, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
```

---

## Phase 2: Important Features

### 2.1 Comprehensive QP Control

#### API Changes
Extend qp_param_t in vp_multi_codec_1_0.h:
```c
typedef struct qp_param_s {
    int qp_min;
    int qp_max;
    int qp_I_base;
    int qp_P_base;
    int qp_B_base;
    int qp_I_min;
    int qp_I_max;
    int qp_P_min;
    int qp_P_max;
    int qp_B_min;
    int qp_B_max;
} qp_param_t; // STREAMBOX_IMPROVE
```

#### Driver Changes
```c
param->minQpI = qp_tbl->qp_I_min;
param->maxQpI = qp_tbl->qp_I_max;
param->minQpP = qp_tbl->qp_P_min;
param->maxQpP = qp_tbl->qp_P_max;
param->minQpB = qp_tbl->qp_B_min;
param->maxQpB = qp_tbl->qp_B_max;
```

#### GStreamer Plugin
Add properties:
```c
PROP_QP_I_MIN = 0
PROP_QP_I_MAX = 51
PROP_QP_P_MIN = 0
PROP_QP_P_MAX = 51
PROP_QP_B_MIN = 0
PROP_QP_B_MAX = 51
```

---

### 2.2 VBV Buffer Control

#### API Changes
```c
typedef struct vl_encode_info {
    // ... existing fields ...
    int vbv_buffer_size_ms;
    // ... existing fields ...
}
```

#### Driver Changes
```c
if (InitParam->vbv_buffer_size_ms > 0) {
    param->vbvBufferSize = InitParam->vbv_buffer_size_ms;
} else {
    param->vbvBufferSize = 500;
}
```

#### GStreamer Plugin
```c
PROP_VBV_BUFFER_SIZE = 0

g_object_class_install_property (gobject_class, PROP_VBV_BUFFER_SIZE,
    g_param_spec_int ("vbv-buffer-size", "VBV Buffer Size",
        "VBV buffer size in milliseconds (0=auto, 10-3000)",
        0, 3000, 0, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
```

---

### 2.3 Runtime Parameter Changes

#### API Changes
```c
typedef enum {
    CHANGE_BITRATE = (1 << 0),
    CHANGE_QP_LIMITS = (1 << 1),
    CHANGE_VBV_SIZE = (1 << 2),
    CHANGE_GOP = (1 << 3)
} param_change_flags_t;

typedef struct vl_param_runtime {
    int* idr;
    int bitrate;
    int frame_rate;
    bool enable_vfr;
    int min_frame_rate;
    
    param_change_flags_t change_flags;
    qp_param_t qp_limits;
    int vbv_buffer_size_ms;
} vl_param_runtime_t; // STREAMBOX_IMPROVE
```

#### Driver Changes
```c
int vl_multi_encoder_change_params(vl_codec_handle_t handle,
                                   vl_param_runtime_t* params) {
    if (params->change_flags & CHANGE_BITRATE) {
        UpdateBitrate(handle, params->bitrate);
    }
    if (params->change_flags & CHANGE_QP_LIMITS) {
        UpdateQpLimits(handle, &params->qp_limits);
    }
}
```

---

### 2.4 HDR10 Metadata Support

#### API Changes
```c
typedef struct mastering_display_metadata {
    struct rational display_primaries[3][2];
    struct rational white_point[2];
    struct rational min_luminance;
    struct rational max_luminance;
} mastering_display_metadata_t; // STREAMBOX_IMPROVE

typedef struct content_light_level {
    uint16_t max_cll;
    uint16_t max_fall;
} content_light_level_t; // STREAMBOX_IMPROVE

typedef struct vl_encode_info {
    // ... existing fields ...
    mastering_display_metadata_t* mastering_display;
    content_light_level_t* content_light_level;
    bool hdr_enable_vui;
} // STREAMBOX_IMPROVE
```

#### Driver Changes
```c
if (InitParam->mastering_display && InitParam->hdr_enable_vui) {
    SetMasteringDisplayMetadata(handle, InitParam->mastering_display);
    SetContentLightLevel(handle, InitParam->content_light_level);
}
```

---

## Phase 3: Advanced Features

### 3.1 CU-Level Rate Control

#### API Changes
```c
typedef struct vl_encode_info {
    // ... existing fields ...
    bool enable_cu_level_rc;
    // ... existing fields ...
}
```

---

### 3.2 HVS QP Enhancement

#### API Changes
```c
typedef struct vl_encode_info {
    // ... existing fields ...
    bool enable_hvs_qp;
    int hvs_qp_scale;
    // ... existing fields ...
}
```

---

### 3.3 Noise Reduction

#### API Changes
```c
typedef struct nr_params {
    bool nr_y_enable;
    bool nr_cb_enable;
    bool nr_cr_enable;
    uint8_t nr_intra_weight_y;
    uint8_t nr_inter_weight_y;
    uint8_t nr_noise_sigma_y;
} nr_params_t; // STREAMBOX_IMPROVE

typedef struct vl_encode_info {
    // ... existing fields ...
    nr_params_t nr_params;
} // STREAMBOX_IMPROVE
```

---

### 3.4 Background Detection

#### API Changes
```c
typedef struct bg_detection_params {
    bool bg_detect_enable;
    uint32_t bg_thr_diff;
    uint32_t bg_thr_mean_diff;
    int32_t bg_lambda_qp;
    int32_t bg_delta_qp;
} bg_detection_params_t; // STREAMBOX_IMPROVE

typedef struct vl_encode_info {
    // ... existing fields ...
    bg_detection_params_t bg_params;
} // STREAMBOX_IMPROVE
```

---

## API Structure Redesign

### New Comprehensive Encoder Configuration Structure

```c
typedef struct vl_encode_info_v2 {
    int width;
    int height;
    int frame_rate;
    int bit_rate;
    int gop;
    vl_img_format_t img_format;
    
    int internal_bit_depth;
    int output_bit_depth;
    
    gop_pattern_t gop_pattern;
    
    rc_mode_t rc_mode;
    
    int vbv_buffer_size_ms;
    
    bool lossless_enable;
    
    qp_param_t qp_params;
    
    bool enable_cu_level_rc;
    bool enable_hvs_qp;
    int hvs_qp_scale;
    
    nr_params_t nr_params;
    
    bg_detection_params_t bg_params;
    
    bool hdr_enable_vui;
    mastering_display_metadata_t* mastering_display;
    content_light_level_t* content_light_level;
    
    bool custom_lambda_enable;
    bool custom_md_enable;
    
    int profile;
    int level;
    uint32_t frame_rotation;
    uint32_t frame_mirroring;
    int bitstream_buf_sz_kb;
    int multi_slice_mode;
    int multi_slice_arg;
    int intra_refresh_mode;
    int intra_refresh_arg;
    int enc_feature_opts;
    uint8_t vui_parameters_present_flag;
    uint8_t video_full_range_flag;
    uint8_t video_signal_type_present_flag;
    uint8_t colour_description_present_flag;
    uint8_t colour_primaries;
    uint8_t transfer_characteristics;
    uint8_t matrix_coefficients;
    bool crop_enable;
    crop_info_multi_t crop;
} vl_encode_info_v2; // STREAMBOX_IMPROVE
```

---

## Implementation Roadmap

### Sprint 1: Foundation (Week 1-2)
1. Add internal_bit_depth and lossless_enable to API
2. Implement 10-bit encoding path in driver
3. Add P010 format to GStreamer plugin
4. Basic testing with 10-bit input

### Sprint 2: GOP & RC (Week 3-4)
1. Add gop_pattern selection to API
2. Implement VBR/CBR mode selection
3. Add B frame support with IBBBP default
4. Test compression efficiency improvements

### Sprint 3: Advanced RC (Week 5-6)
1. Implement per-frame-type QP control
2. Add VBV buffer configuration
3. Implement runtime parameter change API
4. Test with variable bitrate scenarios

### Sprint 4: HDR & Advanced (Week 7-8)
1. Implement HDR10 metadata support
2. Add CU-level RC
3. Add HVS QP enhancement
4. Test HDR10 encoding pipeline

### Sprint 5: Optimization (Week 9-10)
1. Implement noise reduction
2. Implement background detection
3. Performance benchmarking
4. Documentation and examples

---

## Testing Strategy

### Unit Tests
```bash
# 10-bit encoding test
gst-launch-1.0 -e v4l2src device=/dev/video71 \
  ! video/x-raw,format=P010,width=3840,height=2160,framerate=60/1 \
  ! amlvenc internal-bit-depth=10 bitrate=50000 \
  ! video/x-h265,profile=main10 \
  ! h265parse ! filesink location=test_10bit.h265

# B frames test
gst-launch-1.0 -e v4l2src device=/dev/video71 \
  ! video/x-raw,format=NV12,width=3840,height=2160,framerate=60/1 \
  ! amlvenc gop-pattern=ibbbp bitrate=50000 \
  ! video/x-h265 \
  ! h265parse ! filesink location=test_bframe.h265

# CBR mode test
gst-launch-1.0 -e v4l2src device=/dev/video71 \
  ! video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1 \
  ! amlvenc rc-mode=cbr bitrate=10000 vbv-buffer-size=500 \
  ! video/x-h265 \
  ! h265parse ! filesink location=test_cbr.h265

# Lossless test
gst-launch-1.0 -e videotestsrc pattern=snow \
  ! video/x-raw,format=NV12,width=1920,height=1080 \
  ! amlvenc lossless-enable=true \
  ! video/x-h265 \
  ! h265parse ! filesink location=test_lossless.h265
```

### Integration Tests
1. HDR10 loopback test with VDIN
2. Multi-instance encoding
3. Long-duration stability test
4. Variable framerate scenarios
5. Dynamic parameter changes during encoding

---

## Migration Guide

### From Old API to New API

**Old:**
```c
vl_encode_info_t info = {0};
info.width = 1920;
info.height = 1080;
info.bit_rate = 5000000;
info.frame_rate = 30;
vl_codec_handle_t handle = vl_multi_encoder_init(CODEC_ID_H265, info, NULL);
```

**New:**
```c
vl_encode_info_v2_t info = {0};
info.width = 1920;
info.height = 1080;
info.bit_rate = 5000000;
info.frame_rate = 30;

info.internal_bit_depth = 10;

info.gop_pattern = GOP_PATTERN_IBBBP;

info.rc_mode = RC_MODE_CBR;
info.vbv_buffer_size_ms = 500;

info.qp_params.qp_I_min = 10;
info.qp_params.qp_I_max = 35;
info.qp_params.qp_P_min = 15;
info.qp_params.qp_P_max = 40;
info.qp_params.qp_B_min = 20;
info.qp_params.qp_B_max = 45;

vl_codec_handle_t handle = vl_multi_encoder_init_v2(CODEC_ID_H265, info, NULL);
```

---

## Performance Improvements Expected

| Feature | Expected Impact |
|----------|---------------|
| 10-bit Encoding | +30% bitrate for same quality (HDR10) |
| B Frames (IBBBP) | -15-20% bitrate for same quality |
| CBR Mode | Stable bitrate, better for streaming |
| Per-frame QP | Better quality control, -10% bitrate |
| CU-level RC | Better visual quality, +5% encoding time |
| HVS QP | Better subjective quality |
| Noise Reduction | Better quality at low bitrates |
| Background Detection | -10% bitrate for surveillance content |
| Lossless Encoding | Perfect quality, ~3-5x bitrate |

---

## Documentation Requirements

### 1. API Reference Manual
- Complete parameter documentation
- Usage examples
- Migration guide from old API

### 2. GStreamer Plugin Guide
- Property reference
- Pipeline examples
- Performance tuning tips

### 3. Hardware Limitations
- Maximum resolution/bitrate per mode
- Memory requirements
- Known hardware constraints

### 4. Troubleshooting Guide
- Common issues
- Debug logging
- Performance optimization

---

## Conclusion

The Wave521 hardware encoder has excellent capabilities including 10-bit, lossless, and B frame support. However, the software stack only exposes a subset of these features. The most impactful improvements would be:

1. Enabling 10-bit encoding (critical for HDR)
2. Exposing B frame support (improves compression efficiency)
3. Implementing V4L2 encoder driver (improves compatibility)
4. Adding advanced rate control modes (VBR/CBR selection)
5. Exposing lossless encoding (for archival quality)

All required code paths exist in the hardware/library layer - they just need to be exposed through the API and GStreamer plugin.

---

## Appendix: Hardware Register Documentation

### Key Register Fields

#### Rate Control Registers
- RC_ENABLE: Enable/disable rate control
- RC_MODE: Select VBR/CBR/CQP mode
- BITRATE: Target bitrate in bps
- VBV_BUFFER_SIZE: VBV buffer in milliseconds
- FILLER_ENABLE: Enable filler data for CBR

#### QP Control Registers
- MIN_QP_I: Minimum QP for I frames
- MAX_QP_I: Maximum QP for I frames
- MIN_QP_P: Minimum QP for P frames
- MAX_QP_P: Maximum QP for P frames
- MIN_QP_B: Minimum QP for B frames
- MAX_QP_B: Maximum QP for B frames

#### Advanced Feature Registers
- CU_LEVEL_RC_ENABLE: Enable CU-level rate control
- HVS_QP_ENABLE: Enable HVS QP enhancement
- HVS_QP_SCALE: HVS QP scaling factor
- NR_Y_ENABLE: Enable Y component noise reduction
- NR_CB_ENABLE: Enable Cb component noise reduction
- NR_CR_ENABLE: Enable Cr component noise reduction
- BG_DETECT_ENABLE: Enable background detection
- CUSTOM_LAMBDA_ENABLE: Enable custom lambda table
- CUSTOM_MD_ENABLE: Enable custom mode decision

#### Bit Depth Registers
- INTERNAL_BIT_DEPTH: Internal processing bit depth (8 or 10)
- OUTPUT_FORMAT: Output format selection

#### GOP Structure Registers
- GOP_PRESET_IDX: GOP preset index
- CUSTOM_GOP_SIZE: Custom GOP size
- CUSTOM_GOP_PARAMS: Custom GOP parameters

---

## References

### Internal Documents
- encoder_driver_improve.md: Initial analysis document
- AML_MultiEncoder.c: Main encoder implementation
- vp_multi_codec_1_0.h: API header
- gstamlvenc_multienc.c: GStreamer plugin
- vpuapi.h: Low-level VPU API

### External Standards
- ITU-T H.265 (HEVC) Specification
- ITU-T H.264 (AVC) Specification
- SMPTE ST 2084 (HDR10)
- SMPTE ST 2094 (HDR10+)
