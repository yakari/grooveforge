// gf_fft.h — Minimal iterative radix-2 complex FFT (Cooley-Tukey).
//
// A Fourier transform turns a block of samples (a signal over *time*) into a
// block of complex numbers (the same signal described as a sum of *frequencies*).
// Almost every spectral effect in GrooveForge needs that change of view: the
// phase vocoder stretches time by editing frequencies, and an echo canceller
// matches a microphone against a reference by multiplying their spectra rather
// than sliding one waveform along the other a sample at a time.
//
// Lives in its own file because it belongs to no single effect. It was first
// written inside the phase vocoder, which is still its largest user, but
// nothing about it is vocoder-specific.
//
// Design notes:
//
//   - **Iterative, not recursive.** Bit-reversal permutation followed by
//     butterfly layers is the textbook Cooley-Tukey formulation. It is chosen
//     over the recursive form for cache locality and because it adds no stack
//     growth on the audio thread.
//
//   - **Twiddles precomputed once.** The complex rotation factors and the
//     bit-reversal indices are built in gf_fft_init and reused for every
//     transform, so the transform itself touches no transcendental function.
//
//   - **Complex in, complex out.** Real input is fed by zeroing the imaginary
//     parts. A real-optimised transform would be about twice as fast, which
//     no current caller needs.
//
// Real-time safety: gf_fft_init allocates and gf_fft_free releases, so both
// belong in setup and teardown. gf_fft_execute allocates nothing, locks
// nothing and logs nothing — it is safe to call from an audio callback.

#ifndef GF_FFT_H
#define GF_FFT_H

#ifdef __cplusplus
extern "C" {
#endif

/// Precomputed tables for transforms of one fixed size.
///
/// Exposed rather than opaque so callers can embed it by value in their own
/// context struct and keep it in the same allocation.
typedef struct {
    int   n;             ///< FFT size in complex samples. Always a power of two.
    int   log2n;         ///< Number of butterfly layers, i.e. log2(n).
    float* twiddle_cos;  ///< Real part of the rotation factors, length n/2.
    float* twiddle_sin;  ///< Imaginary part of the rotation factors, length n/2.
    int*   bitrev;       ///< Precomputed bit-reversal indices, length n.
} gf_fft;

/// Builds the tables for transforms of [n] complex samples.
///
/// [n] must be a power of two; nothing checks this, and a size that is not
/// will produce silent nonsense rather than an error.
///
/// Returns nonzero on success. On failure the struct is safe to pass to
/// gf_fft_free, which is how callers unwind a partly-built context.
int gf_fft_init(gf_fft* f, int n);

/// Releases the tables and leaves the struct safe to free again.
///
/// Idempotent: the pointers are nulled, so a double free is harmless.
void gf_fft_free(gf_fft* f);

/// Transforms [data] in place.
///
/// [data] is a tightly packed complex array — re[0], im[0], re[1], im[1], … —
/// and therefore holds 2*n floats, not n.
///
/// [inverse] zero runs the forward transform (time to frequency); nonzero runs
/// the inverse (frequency back to time) and divides by n so that a forward
/// followed by an inverse returns the original signal.
void gf_fft_execute(const gf_fft* f, float* data, int inverse);

#ifdef __cplusplus
}
#endif

#endif // GF_FFT_H
