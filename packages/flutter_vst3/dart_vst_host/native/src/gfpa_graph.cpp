// gfpa_graph.cpp — Native interpreter for the audio graph of a user `.gfpd`.
//
// See gfpa_graph.h for the why. In short: the Dart side describes the
// `graph:` section of a descriptor node by node, this file builds the nodes,
// sorts them so every node runs after the nodes that feed it, allocates every
// buffer, and hands back a handle that behaves like a built-in effect.
//
// The node parameters follow the Dart node library exactly (same names, and
// the same mapping from a normalised [0, 1] value to the node's own units),
// so a file behaves the same whichever side reads it.
//
// Audio-thread guarantees, as in gfpa_dsp.cpp:
//   - every buffer is allocated by gfpa_graph_finish();
//   - parameters are std::atomic<float>, written from the Dart isolate and
//     read once per block;
//   - no allocation, lock or logging in gfpa_graph_run().

#include "../include/gfpa_graph.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

/// The live stream rate, defined in gfpa_dsp.cpp (0 before any stream).
float gfpa_stream_sample_rate();

namespace {

constexpr double kPi = 3.14159265358979323846;

/// A stereo pair of sample pointers: one port's audio for the current block.
struct Stereo {
    const float* l = nullptr;
    const float* r = nullptr;
};

/// Clamps [v] to [0, 1].
inline float unit(float v) { return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v); }

// ── Node base ────────────────────────────────────────────────────────────────

/// One processing step of the graph. Every node has exactly one output
/// port, `out`, and the input ports listed by [inputs].
class Node {
public:
    virtual ~Node() = default;

    /// Names of the input ports, in the order process() receives them.
    virtual const std::vector<std::string>& inputs() const = 0;

    /// Index of the node parameter [name], or -1 when the node has none.
    virtual int paramIndex(const std::string& name) const = 0;

    /// Sets parameter [index] to [norm] in [0, 1]. Any thread.
    virtual void setParam(int index, float norm) = 0;

    /// Processes [n] frames from [in] (one entry per input port) into
    /// [outL]/[outR]. Audio thread.
    virtual void process(const Stereo* in, float* outL, float* outR,
                         int32_t n) = 0;

    /// True for `audio_in`, whose output is the graph's input, not a buffer.
    virtual bool isAudioIn() const { return false; }

    /// True for `audio_out`, whose input is the graph's output.
    virtual bool isAudioOut() const { return false; }
};

/// Index of [name] in [names], or -1.
int indexOf(const std::vector<std::string>& names, const std::string& name) {
    auto it = std::find(names.begin(), names.end(), name);
    return it == names.end() ? -1 : static_cast<int>(it - names.begin());
}

const std::vector<std::string> kNoPorts;
const std::vector<std::string> kInPort = {"in"};
const std::vector<std::string> kWetDryPorts = {"wet", "dry"};

// ── audio_in / audio_out ─────────────────────────────────────────────────────

/// The plugin's input. The graph points its output at the host's buffers.
class AudioInNode : public Node {
public:
    const std::vector<std::string>& inputs() const override { return kNoPorts; }
    int paramIndex(const std::string&) const override { return -1; }
    void setParam(int, float) override {}
    void process(const Stereo*, float*, float*, int32_t) override {}
    bool isAudioIn() const override { return true; }
};

/// The plugin's output: whatever reaches its `in` port.
class AudioOutNode : public Node {
public:
    const std::vector<std::string>& inputs() const override { return kInPort; }
    int paramIndex(const std::string&) const override { return -1; }
    void setParam(int, float) override {}
    void process(const Stereo* in, float* outL, float* outR,
                 int32_t n) override {
        std::memcpy(outL, in[0].l, sizeof(float) * static_cast<size_t>(n));
        std::memcpy(outR, in[0].r, sizeof(float) * static_cast<size_t>(n));
    }
    bool isAudioOut() const override { return true; }
};

// ── gain ─────────────────────────────────────────────────────────────────────

/// A volume multiplier. `gain` 0..1 maps to x0..x2, so 0.5 leaves the level
/// unchanged.
class GainNode : public Node {
public:
    const std::vector<std::string>& inputs() const override { return kInPort; }
    int paramIndex(const std::string& name) const override {
        return name == "gain" ? 0 : -1;
    }
    void setParam(int, float norm) override { gain_.store(norm * 2.0f); }
    void process(const Stereo* in, float* outL, float* outR,
                 int32_t n) override {
        const float g = gain_.load(std::memory_order_relaxed);
        for (int32_t i = 0; i < n; ++i) {
            outL[i] = in[0].l[i] * g;
            outR[i] = in[0].r[i] * g;
        }
    }

private:
    std::atomic<float> gain_{1.0f};
};

// ── wet_dry ──────────────────────────────────────────────────────────────────

/// Blends the effected signal (`wet`) with the original (`dry`):
/// out = dry * (1 - mix) + wet * mix.
class WetDryNode : public Node {
public:
    const std::vector<std::string>& inputs() const override {
        return kWetDryPorts;
    }
    int paramIndex(const std::string& name) const override {
        return name == "mix" ? 0 : -1;
    }
    void setParam(int, float norm) override { mix_.store(unit(norm)); }
    void process(const Stereo* in, float* outL, float* outR,
                 int32_t n) override {
        const float w = mix_.load(std::memory_order_relaxed);
        const float d = 1.0f - w;
        const Stereo& wet = in[0];
        const Stereo& dry = in[1];
        for (int32_t i = 0; i < n; ++i) {
            outL[i] = dry.l[i] * d + wet.l[i] * w;
            outR[i] = dry.r[i] * d + wet.r[i] * w;
        }
    }

private:
    std::atomic<float> mix_{0.5f};
};

// ── biquad_filter ────────────────────────────────────────────────────────────

/// A second-order filter from the Audio EQ Cookbook (R. Bristow-Johnson),
/// the same formulas as the Dart GFDspBiquadFilterNode. Seven shapes: low
/// pass, high pass, band pass, notch, peaking, low shelf, high shelf.
class BiquadNode : public Node {
public:
    const std::vector<std::string>& inputs() const override { return kInPort; }

    int paramIndex(const std::string& name) const override {
        static const std::vector<std::string> names = {"freq", "q", "gain",
                                                       "mode"};
        return indexOf(names, name);
    }

    /// Stores the knob in the filter's own units; the audio thread picks the
    /// change up at its next block through [version_].
    void setParam(int index, float norm) override {
        switch (index) {
            // 20 Hz to 20 kHz, exponential so each octave gets equal travel.
            case 0: freq_.store(20.0f * std::pow(1000.0f, norm)); break;
            // Q 0.1 (very wide) to 20 (very narrow), exponential.
            case 1: q_.store(0.1f * std::pow(200.0f, norm)); break;
            // Boost or cut for the peaking and shelf shapes, ±24 dB.
            case 2: gainDb_.store(norm * 48.0f - 24.0f); break;
            // One of the seven shapes.
            case 3: mode_.store(static_cast<int>(std::lround(unit(norm) * 6.0f))); break;
            default: return;
        }
        version_.fetch_add(1, std::memory_order_release);
    }

    void process(const Stereo* in, float* outL, float* outR,
                 int32_t n) override {
        refreshCoefficients();
        filter(in[0].l, outL, n, s1L_, s2L_);
        filter(in[0].r, outR, n, s1R_, s2R_);
    }

private:
    std::atomic<float> freq_{1000.0f};
    std::atomic<float> q_{0.707f};
    std::atomic<float> gainDb_{0.0f};
    std::atomic<int> mode_{0};

    /// Bumped by every knob change; compared with [seen_] on the audio
    /// thread so the coefficients are only recomputed when needed.
    std::atomic<unsigned> version_{1};
    unsigned seen_ = 0;
    float seenRate_ = 0.0f;

    double b0_ = 1, b1_ = 0, b2_ = 0, a1_ = 0, a2_ = 0;
    double s1L_ = 0, s2L_ = 0, s1R_ = 0, s2R_ = 0;

    /// Audio thread: recomputes the coefficients after a knob change or a
    /// change of stream rate. A handful of trig calls, no allocation.
    void refreshCoefficients() {
        const unsigned v = version_.load(std::memory_order_acquire);
        float rate = gfpa_stream_sample_rate();
        if (rate <= 0.0f) rate = 48000.0f;
        if (v == seen_ && rate == seenRate_) return;
        seen_ = v;
        seenRate_ = rate;
        compute(rate);
    }

    /// The cookbook formulas, normalised so a0 = 1.
    void compute(double fs) {
        const double f0 = std::min<double>(std::max(20.0f, freq_.load()),
                                           fs / 2.0 - 1.0);
        const double w0 = 2.0 * kPi * f0 / fs;
        const double cw = std::cos(w0);
        const double alpha = std::sin(w0) / (2.0 * q_.load());
        const double A = std::pow(10.0, gainDb_.load() / 40.0);
        const double sa = 2.0 * std::sqrt(A) * alpha;
        double b0, b1, b2, a0, a1, a2;
        switch (mode_.load()) {
            case 1:  // high pass
                b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2;
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha; break;
            case 2:  // band pass, 0 dB peak
                b0 = alpha; b1 = 0; b2 = -alpha;
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha; break;
            case 3:  // notch
                b0 = 1; b1 = -2 * cw; b2 = 1;
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha; break;
            case 4:  // peaking
                b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A;
                a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A; break;
            case 5:  // low shelf
                b0 = A * ((A + 1) - (A - 1) * cw + sa);
                b1 = 2 * A * ((A - 1) - (A + 1) * cw);
                b2 = A * ((A + 1) - (A - 1) * cw - sa);
                a0 = (A + 1) + (A - 1) * cw + sa;
                a1 = -2 * ((A - 1) + (A + 1) * cw);
                a2 = (A + 1) + (A - 1) * cw - sa; break;
            case 6:  // high shelf
                b0 = A * ((A + 1) + (A - 1) * cw + sa);
                b1 = -2 * A * ((A - 1) + (A + 1) * cw);
                b2 = A * ((A + 1) + (A - 1) * cw - sa);
                a0 = (A + 1) - (A - 1) * cw + sa;
                a1 = 2 * ((A - 1) - (A + 1) * cw);
                a2 = (A + 1) - (A - 1) * cw - sa; break;
            default:  // low pass
                b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2;
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha; break;
        }
        b0_ = b0 / a0; b1_ = b1 / a0; b2_ = b2 / a0;
        a1_ = a1 / a0; a2_ = a2 / a0;
    }

    /// Transposed direct form II, one channel. The state is kept in double:
    /// a low corner at a high sample rate loses precision in float.
    void filter(const float* x, float* y, int32_t n, double& s1, double& s2) {
        for (int32_t i = 0; i < n; ++i) {
            const double out = b0_ * x[i] + s1;
            s1 = b1_ * x[i] - a1_ * out + s2;
            s2 = b2_ * x[i] - a2_ * out;
            y[i] = static_cast<float>(out);
        }
    }
};

// ── Built-in effects as nodes ────────────────────────────────────────────────

/// How a node parameter reaches the built-in effect: the effect's own
/// parameter id, and the conversion from the node's [0, 1] to that
/// parameter's units (the units the effect's `.gfpd` panel uses).
struct EffectParam {
    const char* nodeName;
    const char* effectId;
    float (*convert)(float norm);
};

/// Everything needed to run a built-in effect as a node: which effect, how
/// its parameters map, and the values it starts with. The start values are
/// the Dart node's defaults, plus `mix` at 100 % so the node outputs only
/// the effect: blending with the dry signal is the wet_dry node's job.
struct EffectSpec {
    const char* type;
    const char* pluginId;
    std::vector<EffectParam> params;
    std::vector<std::pair<const char*, float>> start;
};

float asIs(float n) { return n; }
float toggle(float n) { return n >= 0.5f ? 1.0f : 0.0f; }
float beatDiv(float n) { return std::round(unit(n) * 5.0f); }
float percent(float n) { return n * 100.0f; }

/// The five effects the Dart node library offers, with the same mappings as
/// its GFDsp*Node classes.
const std::vector<EffectSpec>& effectSpecs() {
    static const std::vector<EffectSpec> specs = {
        {"freeverb", "com.grooveforge.reverb",
         {{"roomSize", "room_size", asIs},
          {"damping", "damping", asIs},
          {"width", "width", asIs}},
         {{"mix", 100}, {"room_size", 0}, {"damping", 0.5f}, {"width", 1}}},
        {"delay", "com.grooveforge.delay",
         {{"timeMs", "time", [](float n) { return 1 + n * 1999; }},
          {"feedback", "feedback", [](float n) { return n * 99; }},
          {"bpmSync", "bpm_sync", toggle},
          {"beatDiv", "beat_div", beatDiv}},
         {{"mix", 100}, {"time", 500}, {"feedback", 40},
          {"bpm_sync", 0}, {"beat_div", 2}}},
        {"wah_filter", "com.grooveforge.wah",
         {{"center", "center", [](float n) { return 200 * std::pow(20.0f, n); }},
          {"resonance", "resonance", [](float n) { return 0.5f + n * 19.5f; }},
          {"rate", "rate", [](float n) { return 0.1f + n * 9.9f; }},
          {"depth", "depth", unit},
          {"waveform", "waveform", [](float n) { return std::round(unit(n) * 2); }},
          {"bpmSync", "bpm_sync", toggle},
          {"beatDiv", "beat_div", beatDiv},
          {"mode", "mode", toggle},
          {"pedal", "pedal", percent}},
         {{"mix", 100}, {"center", 1200}, {"resonance", 5}, {"rate", 1},
          {"depth", 0.8f}, {"waveform", 0}, {"bpm_sync", 0}, {"beat_div", 2},
          {"mode", 0}, {"pedal", 50}}},
        {"compressor", "com.grooveforge.compressor",
         {{"threshold", "threshold", [](float n) { return -60 + n * 60; }},
          {"ratio", "ratio", [](float n) { return 1 + n * 19; }},
          {"attack", "attack", [](float n) { return 0.1f + n * 199.9f; }},
          {"release", "release", [](float n) { return 10 + n * 1990; }},
          {"makeup", "makeup", [](float n) { return n * 24; }}},
         {{"threshold", -18}, {"ratio", 4}, {"attack", 10},
          {"release", 100}, {"makeup", 0}}},
        {"chorus", "com.grooveforge.chorus",
         {{"rate", "rate", [](float n) { return 0.1f + n * 9.9f; }},
          {"depth", "depth", unit},
          {"delay", "delay", [](float n) { return 5 + n * 45; }},
          {"mix", "mix", percent},
          {"feedback", "feedback", [](float n) { return n * 90; }},
          {"bpmSync", "bpm_sync", toggle},
          {"beatDiv", "beat_div", beatDiv}},
         {{"rate", 0.5f}, {"depth", 0.5f}, {"delay", 20}, {"mix", 50},
          {"feedback", 0}, {"bpm_sync", 0}, {"beat_div", 3}}},
    };
    return specs;
}

/// A built-in effect (reverb, delay, …) running as one node. The effect is
/// created through gfpa_dsp_create() and driven through the same C calls the
/// host uses, so its code is not touched at all.
class EffectNode : public Node {
public:
    EffectNode(const EffectSpec& spec, GfpaDspHandle effect)
        : spec_(spec), effect_(effect), run_(gfpa_dsp_insert_fn(effect)) {
        for (const auto& s : spec.start) gfpa_dsp_set_param(effect_, s.first, s.second);
    }
    ~EffectNode() override { gfpa_dsp_destroy(effect_); }

    const std::vector<std::string>& inputs() const override { return kInPort; }

    int paramIndex(const std::string& name) const override {
        for (size_t i = 0; i < spec_.params.size(); ++i) {
            if (name == spec_.params[i].nodeName) return static_cast<int>(i);
        }
        return -1;
    }

    /// Converts and forwards; the effect stores it in an atomic.
    void setParam(int index, float norm) override {
        const EffectParam& p = spec_.params[static_cast<size_t>(index)];
        gfpa_dsp_set_param(effect_, p.effectId, p.convert(norm));
    }

    void process(const Stereo* in, float* outL, float* outR,
                 int32_t n) override {
        run_(in[0].l, in[0].r, outL, outR, n, gfpa_dsp_userdata(effect_));
    }

private:
    const EffectSpec& spec_;
    GfpaDspHandle effect_;
    GfpaInsertFn run_;
};

/// Creates a node of [type], or nullptr when the type is unknown or the
/// effect behind it could not be created.
std::unique_ptr<Node> makeNode(const std::string& type, int32_t sr,
                               int32_t block) {
    if (type == "audio_in") return std::make_unique<AudioInNode>();
    if (type == "audio_out") return std::make_unique<AudioOutNode>();
    if (type == "gain") return std::make_unique<GainNode>();
    if (type == "wet_dry") return std::make_unique<WetDryNode>();
    if (type == "biquad_filter") return std::make_unique<BiquadNode>();
    for (const auto& spec : effectSpecs()) {
        if (type != spec.type) continue;
        GfpaDspHandle effect = gfpa_dsp_create(spec.pluginId, sr, block);
        if (!effect) return nullptr;
        return std::make_unique<EffectNode>(spec, effect);
    }
    return nullptr;
}

// ── Builder ──────────────────────────────────────────────────────────────────

/// One wire: [from]'s output into input port [port] of [to].
struct Edge {
    int from;
    int to;
    int port;
};

/// A plugin parameter, and the node parameters that follow it.
struct Param {
    std::string id;
    float min;
    float max;
    float def;
    std::vector<std::pair<int, int>> targets;  ///< (node index, param index)
};

/// A graph being described. Nodes are kept in declaration order until
/// gfpa_graph_finish() sorts them.
struct Builder {
    int32_t sampleRate;
    int32_t block;
    std::vector<std::unique_ptr<Node>> nodes;
    std::unordered_map<std::string, int> nodeIndex;
    std::vector<Edge> edges;
    std::vector<Param> params;

    int find(const char* id) const {
        auto it = nodeIndex.find(id);
        return it == nodeIndex.end() ? -1 : it->second;
    }

    Param* findParam(const char* id) {
        for (auto& p : params) if (p.id == id) return &p;
        return nullptr;
    }
};

}  // namespace

// ── Finished graph ───────────────────────────────────────────────────────────

/// A graph ready to process. Built once by gfpa_graph_finish(); after that
/// only parameter values change.
struct GfpaGraph {
    /// Nodes in processing order: each runs after every node that feeds it.
    std::vector<std::unique_ptr<Node>> nodes;

    /// For each node, each input port: the nodes wired into it.
    std::vector<std::vector<std::vector<int>>> sources;

    /// For each node, its output buffers ([block] frames per channel).
    std::vector<std::vector<float>> outL, outR;

    /// For each node, each input port: a buffer to sum several wires into
    /// (empty when the port has fewer than two).
    std::vector<std::vector<std::vector<float>>> sumL, sumR;

    /// For each node, the Stereo array process() receives.
    std::vector<std::vector<Stereo>> inputs;

    /// For each node, the current block's output, as seen by downstream
    /// nodes. Points into outL/outR, or at the host's input for audio_in.
    std::vector<Stereo> outputs;

    std::vector<float> silence;
    std::vector<Param> params;
    int audioOut = -1;
    int32_t block = 0;
};

namespace {

/// Kahn's algorithm: repeatedly takes the first node (in declaration order)
/// whose inputs are all done. Returns false when some nodes are never ready,
/// which means the wires form a loop.
bool sortNodes(const Builder& b, std::vector<int>& order) {
    const size_t count = b.nodes.size();
    std::vector<int> pending(count, 0);
    for (const auto& e : b.edges) ++pending[static_cast<size_t>(e.to)];
    std::vector<bool> done(count, false);
    while (order.size() < count) {
        int next = -1;
        for (size_t i = 0; i < count && next < 0; ++i) {
            if (!done[i] && pending[i] == 0) next = static_cast<int>(i);
        }
        if (next < 0) return false;
        done[static_cast<size_t>(next)] = true;
        order.push_back(next);
        for (const auto& e : b.edges) {
            if (e.from == next) --pending[static_cast<size_t>(e.to)];
        }
    }
    return true;
}

/// Counts the nodes for which [test] holds.
template <typename F>
int countNodes(const Builder& b, F test) {
    int n = 0;
    for (const auto& node : b.nodes) if (test(*node)) ++n;
    return n;
}

/// Moves the sorted nodes into [g] and allocates every buffer they use.
void allocate(Builder& b, const std::vector<int>& order, GfpaGraph& g) {
    const size_t count = order.size();
    const size_t frames = static_cast<size_t>(b.block);
    std::vector<int> position(count);
    for (size_t i = 0; i < count; ++i) position[static_cast<size_t>(order[i])] = static_cast<int>(i);

    g.block = b.block;
    g.silence.assign(frames, 0.0f);
    g.sources.resize(count);
    g.sumL.resize(count);
    g.sumR.resize(count);
    g.inputs.resize(count);
    g.outputs.resize(count);
    g.outL.resize(count);
    g.outR.resize(count);
    for (size_t i = 0; i < count; ++i) {
        g.nodes.push_back(std::move(b.nodes[static_cast<size_t>(order[i])]));
        const size_t ports = g.nodes[i]->inputs().size();
        g.sources[i].resize(ports);
        g.sumL[i].resize(ports);
        g.sumR[i].resize(ports);
        g.inputs[i].resize(ports);
        g.outL[i].assign(frames, 0.0f);
        g.outR[i].assign(frames, 0.0f);
        g.outputs[i] = {g.outL[i].data(), g.outR[i].data()};
        if (g.nodes[i]->isAudioOut()) g.audioOut = static_cast<int>(i);
    }
    for (const auto& e : b.edges) {
        const size_t to = static_cast<size_t>(position[static_cast<size_t>(e.to)]);
        g.sources[to][static_cast<size_t>(e.port)].push_back(position[static_cast<size_t>(e.from)]);
    }
    for (size_t i = 0; i < count; ++i) {
        for (size_t p = 0; p < g.sources[i].size(); ++p) {
            if (g.sources[i][p].size() < 2) continue;
            g.sumL[i][p].assign(frames, 0.0f);
            g.sumR[i][p].assign(frames, 0.0f);
        }
    }
    // Re-point the parameter targets at the sorted positions.
    g.params = std::move(b.params);
    for (auto& p : g.params) {
        for (auto& t : p.targets) t.first = position[static_cast<size_t>(t.first)];
    }
}

/// Sends [p]'s physical [value] to every node parameter bound to it.
void applyParam(GfpaGraph& g, const Param& p, float value) {
    const float range = p.max - p.min;
    const float norm = range == 0.0f ? 0.0f : unit((value - p.min) / range);
    for (const auto& t : p.targets) {
        g.nodes[static_cast<size_t>(t.first)]->setParam(t.second, norm);
    }
}

/// Audio thread: gathers what reaches input port [p] of node [i] into
/// g.inputs[i][p] for [n] frames. One wire is used as is; several are summed
/// into the port's own buffer; none gives silence.
void gatherInput(GfpaGraph& g, size_t i, size_t p, int32_t n) {
    const std::vector<int>& from = g.sources[i][p];
    if (from.empty()) {
        g.inputs[i][p] = {g.silence.data(), g.silence.data()};
        return;
    }
    if (from.size() == 1) {
        g.inputs[i][p] = g.outputs[static_cast<size_t>(from[0])];
        return;
    }
    float* l = g.sumL[i][p].data();
    float* r = g.sumR[i][p].data();
    std::memset(l, 0, sizeof(float) * static_cast<size_t>(n));
    std::memset(r, 0, sizeof(float) * static_cast<size_t>(n));
    for (int src : from) {
        const Stereo& s = g.outputs[static_cast<size_t>(src)];
        for (int32_t k = 0; k < n; ++k) {
            l[k] += s.l[k];
            r[k] += s.r[k];
        }
    }
    g.inputs[i][p] = {l, r};
}

/// Audio thread: runs every node once over [n] <= block frames.
void runPiece(GfpaGraph& g, const float* inL, const float* inR, float* outL,
              float* outR, int32_t n) {
    for (size_t i = 0; i < g.nodes.size(); ++i) {
        Node& node = *g.nodes[i];
        if (node.isAudioIn()) {
            g.outputs[i] = {inL, inR};
            continue;
        }
        for (size_t p = 0; p < g.inputs[i].size(); ++p) gatherInput(g, i, p, n);
        node.process(g.inputs[i].data(), g.outL[i].data(), g.outR[i].data(), n);
    }
    const Stereo& result = g.outputs[static_cast<size_t>(g.audioOut)];
    std::memcpy(outL, result.l, sizeof(float) * static_cast<size_t>(n));
    std::memcpy(outR, result.r, sizeof(float) * static_cast<size_t>(n));
}

}  // namespace

// ── Internal hooks ───────────────────────────────────────────────────────────

void gfpa_graph_run(GfpaGraph* g, const float* inL, const float* inR,
                    float* outL, float* outR, int32_t frames) {
    // A host block larger than the graph's buffers is processed in pieces.
    for (int32_t done = 0; done < frames; done += g->block) {
        const int32_t n = std::min(g->block, frames - done);
        runPiece(*g, inL + done, inR + done, outL + done, outR + done, n);
    }
}

void gfpa_graph_param(GfpaGraph* g, const char* paramId, float value) {
    for (const auto& p : g->params) {
        if (p.id == paramId) applyParam(*g, p, value);
    }
}

void gfpa_graph_free(GfpaGraph* g) { delete g; }

// ── C API ────────────────────────────────────────────────────────────────────

extern "C" {

GfpaGraphBuilder gfpa_graph_begin(int32_t sampleRate, int32_t blockSize) {
    auto* b = new Builder();
    b->sampleRate = sampleRate > 0 ? sampleRate : 48000;
    b->block = blockSize > 0 ? blockSize : 4096;
    return b;
}

int32_t gfpa_graph_add_node(GfpaGraphBuilder handle, const char* nodeId,
                            const char* type) {
    auto* b = static_cast<Builder*>(handle);
    if (!b || !nodeId || !type || b->find(nodeId) >= 0) return -1;
    std::unique_ptr<Node> node = makeNode(type, b->sampleRate, b->block);
    if (!node) return -1;
    b->nodeIndex[nodeId] = static_cast<int>(b->nodes.size());
    b->nodes.push_back(std::move(node));
    return 0;
}

int32_t gfpa_graph_connect(GfpaGraphBuilder handle, const char* fromNode,
                           const char* fromPort, const char* toNode,
                           const char* toPort) {
    auto* b = static_cast<Builder*>(handle);
    if (!b || !fromPort || !toPort) return -1;
    const int from = b->find(fromNode);
    const int to = b->find(toNode);
    if (from < 0 || to < 0) return -1;
    // Every node has one output, `out`; audio_out has nothing to give.
    if (std::strcmp(fromPort, "out") != 0) return -1;
    if (b->nodes[static_cast<size_t>(from)]->isAudioOut()) return -1;
    const int port = indexOf(b->nodes[static_cast<size_t>(to)]->inputs(), toPort);
    if (port < 0) return -1;
    b->edges.push_back({from, to, port});
    return 0;
}

int32_t gfpa_graph_add_param(GfpaGraphBuilder handle, const char* paramId,
                             double min, double max, double defaultValue) {
    auto* b = static_cast<Builder*>(handle);
    if (!b || !paramId || b->findParam(paramId)) return -1;
    b->params.push_back({paramId, static_cast<float>(min),
                         static_cast<float>(max),
                         static_cast<float>(defaultValue), {}});
    return 0;
}

int32_t gfpa_graph_bind(GfpaGraphBuilder handle, const char* paramId,
                        const char* nodeId, const char* nodeParam) {
    auto* b = static_cast<Builder*>(handle);
    if (!b || !paramId || !nodeParam) return -1;
    Param* p = b->findParam(paramId);
    const int node = b->find(nodeId);
    if (!p || node < 0) return -1;
    const int index = b->nodes[static_cast<size_t>(node)]->paramIndex(nodeParam);
    if (index < 0) return -1;
    p->targets.emplace_back(node, index);
    return 0;
}

int32_t gfpa_graph_set_const(GfpaGraphBuilder handle, const char* nodeId,
                             const char* nodeParam, double normalized) {
    auto* b = static_cast<Builder*>(handle);
    if (!b || !nodeParam) return -1;
    const int node = b->find(nodeId);
    if (node < 0) return -1;
    Node& n = *b->nodes[static_cast<size_t>(node)];
    const int index = n.paramIndex(nodeParam);
    if (index < 0) return -1;
    n.setParam(index, static_cast<float>(normalized));
    return 0;
}

GfpaDspHandle gfpa_graph_finish(GfpaGraphBuilder handle) {
    std::unique_ptr<Builder> b(static_cast<Builder*>(handle));
    if (!b) return nullptr;
    const auto isIn = [](const Node& n) { return n.isAudioIn(); };
    const auto isOut = [](const Node& n) { return n.isAudioOut(); };
    if (countNodes(*b, isOut) != 1 || countNodes(*b, isIn) > 1) return nullptr;
    std::vector<int> order;
    if (!sortNodes(*b, order)) return nullptr;

    auto* g = new GfpaGraph();
    allocate(*b, order, *g);
    // Each bound node parameter starts at its plugin parameter's default; a
    // constant set on the same node parameter is overridden, as in Dart.
    for (const auto& p : g->params) applyParam(*g, p, p.def);
    return gfpa_dsp_wrap_graph(g, static_cast<float>(b->sampleRate));
}

void gfpa_graph_abort(GfpaGraphBuilder handle) {
    delete static_cast<Builder*>(handle);
}

}  // extern "C"
