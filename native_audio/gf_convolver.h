// gf_convolver.h — Zero-latency convolution with a fixed impulse response.
//
// Convolution is how a recorded speaker cabinet is applied to a signal: an
// impulse response (IR) is what the cabinet and its microphone did to a single
// click, and convolving the guitar with it makes the guitar sound as if it
// had gone through that cabinet. Each output sample is a weighted sum of the
// last N input samples, N being the IR's length — thousands of taps, too many
// to compute one by one at audio rates.
//
// The usual cure is to do the sum in the frequency domain with an FFT, block
// by block, which is cheap but delays the output by a block. Here the IR is
// split in two (the "hybrid" scheme of Gardner, "Efficient Convolution
// without Input-Output Delay", JAES 1995, in its uniform-partition form):
//
//   - the first 128 taps — the attack, where most of a cabinet's character
//     is — are summed directly, sample by sample, so nothing is delayed;
//   - the rest is cut into 128-tap partitions, each one convolved with an FFT
//     once every 128 input samples ("uniformly partitioned overlap-save").
//     Partition k only affects output from 128·k samples on, so its result is
//     always ready before it is needed.
//
// The output is the exact linear convolution, to float rounding, with no
// added latency.
//
// Real-time safety: gf_convolver_create allocates; gf_convolver_process and
// gf_convolver_reset never allocate, lock or log.

#ifndef GF_CONVOLVER_H
#define GF_CONVOLVER_H

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle. All state is owned by this struct.
typedef struct gf_convolver gf_convolver;

/// Builds a convolver for the [len]-tap impulse response [ir], which is
/// copied. Allocates: never call it from the audio thread. Returns NULL on
/// bad input or out-of-memory.
gf_convolver* gf_convolver_create(const float* ir, int len);

/// Frees a convolver. Safe to pass NULL.
void gf_convolver_destroy(gf_convolver* c);

/// Clears the input history, as if the convolver had only ever heard
/// silence. Allocation-free.
void gf_convolver_reset(gf_convolver* c);

/// Convolves [n] samples. [in] and [out] may be the same buffer. Any block
/// size is accepted. Allocation-free.
void gf_convolver_process(gf_convolver* c, const float* in, float* out, int n);

/// The impulse response's length in taps.
int gf_convolver_length(const gf_convolver* c);

#ifdef __cplusplus
}
#endif

#endif // GF_CONVOLVER_H
