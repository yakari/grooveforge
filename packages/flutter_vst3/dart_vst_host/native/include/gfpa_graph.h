// gfpa_graph.h — Native interpreter for the audio graph of a user `.gfpd`.
//
// The effects that ship with GrooveForge each have a hand-written C++ class,
// chosen by plugin id in gfpa_dsp_create(). A `.gfpd` file written by a user
// has an id the native side has never heard of, so for a long time it showed
// its panel and made no sound.
//
// This interpreter builds the file's `graph:` section natively instead: the
// Dart side reads the descriptor and describes it node by node through the
// builder calls below, then gets back an ordinary GfpaDspHandle. That handle
// goes through gfpa_dsp_set_param, gfpa_dsp_set_bypass, gfpa_dsp_insert_fn
// and gfpa_dsp_destroy exactly like a built-in effect's, so the insert chain,
// bypass and parameter code paths are the same ones the bundled effects use.
//
// Node types (the same names and parameters as the Dart node library in
// grooveforge_plugin_api, see HOW_TO_CREATE_A_PLUGIN.md):
//   audio_in, audio_out, gain, wet_dry, biquad_filter,
//   freeverb, delay, wah_filter, compressor, chorus.
// The last five run the built-in effect classes unchanged, set to 100 % wet;
// mixing is the graph's job (wet_dry).
//
// Threading: every builder call allocates and must run off the audio thread.
// Once gfpa_graph_finish() returns, processing allocates nothing.
#pragma once
#include "gfpa_dsp.h"

#ifdef __cplusplus
extern "C" {
#endif

/// A graph being described, before gfpa_graph_finish() turns it into an
/// effect. Opaque.
typedef void* GfpaGraphBuilder;

/// Starts describing a graph that will run at [sampleRate] Hz on blocks of
/// up to [blockSize] frames (larger blocks are processed in pieces).
DVH_API GfpaGraphBuilder gfpa_graph_begin(int32_t sampleRate,
                                          int32_t blockSize);

/// Adds node [nodeId] of type [type]. Returns 0, or -1 when the type is
/// unknown or the id is already used.
DVH_API int32_t gfpa_graph_add_node(GfpaGraphBuilder builder,
                                    const char* nodeId, const char* type);

/// Connects output port [fromPort] of [fromNode] to input port [toPort] of
/// [toNode]. Several connections into one input are summed. Returns 0, or -1
/// when a node or port does not exist.
DVH_API int32_t gfpa_graph_connect(GfpaGraphBuilder builder,
                                   const char* fromNode, const char* fromPort,
                                   const char* toNode, const char* toPort);

/// Declares plugin parameter [paramId] with the range and default of the
/// `.gfpd` `parameters:` entry. Returns 0, or -1 for a duplicate id.
DVH_API int32_t gfpa_graph_add_param(GfpaGraphBuilder builder,
                                     const char* paramId, double min,
                                     double max, double defaultValue);

/// Makes node parameter [nodeParam] of [nodeId] follow plugin parameter
/// [paramId] (`{ param: id }` in the file). Returns 0, or -1 when the
/// parameter, the node or the node parameter does not exist.
DVH_API int32_t gfpa_graph_bind(GfpaGraphBuilder builder, const char* paramId,
                                const char* nodeId, const char* nodeParam);

/// Sets node parameter [nodeParam] of [nodeId] once, to [normalized] in
/// [0, 1] (`{ value: n }` in the file). Returns 0, or -1 when the node or the
/// node parameter does not exist.
DVH_API int32_t gfpa_graph_set_const(GfpaGraphBuilder builder,
                                     const char* nodeId,
                                     const char* nodeParam, double normalized);

/// Checks the graph and turns it into an effect. Returns NULL when the graph
/// has no `audio_out`, more than one `audio_in` or `audio_out`, or a loop.
/// The builder is freed in every case.
DVH_API GfpaDspHandle gfpa_graph_finish(GfpaGraphBuilder builder);

/// Frees a builder without making an effect, after a failed call.
DVH_API void gfpa_graph_abort(GfpaGraphBuilder builder);

#ifdef __cplusplus
}

// ── Internal hooks between gfpa_graph.cpp and gfpa_dsp.cpp ───────────────────
//
// Not part of the C API: gfpa_dsp.cpp owns GfpaDspInstance, the wrapper every
// handle points at, and calls these to run a graph held inside one.

/// A finished graph, ready to process.
struct GfpaGraph;

/// Processes [frames] stereo frames through [graph]. Audio thread; no
/// allocation. [inL]/[inR] and [outL]/[outR] must not overlap.
void gfpa_graph_run(GfpaGraph* graph, const float* inL, const float* inR,
                    float* outL, float* outR, int32_t frames);

/// Sets plugin parameter [paramId] to [physicalValue] (in the range the
/// `.gfpd` declares). Any thread; unknown ids are ignored.
void gfpa_graph_param(GfpaGraph* graph, const char* paramId,
                      float physicalValue);

/// Frees [graph] and every effect inside it.
void gfpa_graph_free(GfpaGraph* graph);

/// Wraps [graph] in a GfpaDspInstance (defined in gfpa_dsp.cpp) so it can be
/// handled like any built-in effect. Takes ownership of [graph].
GfpaDspHandle gfpa_dsp_wrap_graph(GfpaGraph* graph, float sampleRate);
#endif
