#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <math.h>
#include <stdio.h>
#include <stdbool.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "GrooveForgeAudio", __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "GrooveForgeAudio", __VA_ARGS__)
#else
#define LOGE(...) printf(__VA_ARGS__)
#define LOGI(...) printf(__VA_ARGS__)
#endif

// Global state
static ma_context context;
static ma_device device;
static bool isInitialized = false;
static float currentPeakLevel = 0.0f;

// Data callback for capturing audio
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount)
{
    // In capture mode, pInput will contain the incoming audio data
    if (pInput == NULL) return;

    const float* pFrames = (const float*)pInput;
    float peak = 0.0f;

    // Calculate the peak level of the current buffer
    // Assuming 1 channel (mono) or processing interleaved channels
    ma_uint32 totalSamples = frameCount * pDevice->capture.channels;
    
    for (ma_uint32 i = 0; i < totalSamples; ++i) {
        float sample = fabsf(pFrames[i]);
        if (sample > peak) {
            peak = sample;
        }
    }

    currentPeakLevel = peak;
    (void)pOutput; // Output is unused in capture-only mode
}

#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// Initialize and start audio capture
EXPORT int start_audio_capture() {
    if (isInitialized) return 0; // Already running

    ma_result result;
    ma_device_config deviceConfig;

    result = ma_context_init(NULL, 0, NULL, &context);
    if (result != MA_SUCCESS) {
        LOGE("Failed to initialize context: %d\n", result);
        return -1;
    }

    deviceConfig = ma_device_config_init(ma_device_type_capture);
    deviceConfig.capture.pDeviceID = NULL; // Default input device
    deviceConfig.capture.format    = ma_format_f32;
    deviceConfig.capture.channels  = 1;
    deviceConfig.sampleRate        = 48000;
    deviceConfig.dataCallback      = data_callback;

    result = ma_device_init(&context, &deviceConfig, &device);
    if (result != MA_SUCCESS) {
        LOGE("Failed to initialize device: %d\n", result);
        ma_context_uninit(&context);
        return -2;
    }

    result = ma_device_start(&device);
    if (result != MA_SUCCESS) {
        LOGE("Failed to start device: %d\n", result);
        ma_device_uninit(&device);
        ma_context_uninit(&context);
        return -3;
    }

    LOGI("Audio capture started successfully!");

    isInitialized = true;
    return 0; // Success
}

// Stop audio capture and cleanup
EXPORT void stop_audio_capture() {
    if (!isInitialized) return;

    ma_device_stop(&device);
    ma_device_uninit(&device);
    ma_context_uninit(&context);

    isInitialized = false;
    currentPeakLevel = 0.0f;
}

// Get the current peak level (0.0 to 1.0)
EXPORT float get_current_peak_level() {
    // Optional: Add basic smoothing/decay logic here instead of Dart if needed
    return currentPeakLevel;
}
