# How to Create a GrooveForge Plugin

GrooveForge plugins use the `.gfpd` (**GrooveForge Plugin Descriptor**) format — a human-readable YAML file that fully describes a plugin: its identity, its DSP signal graph, its parameters, and how its UI panel should look. No Dart or Flutter code is required for standard effects and instruments.

---

## Quick Start — Copy a Template

The fastest way to start is to copy one of the bundled plugins and modify it:

1. Open any `.gfpd` file from `assets/plugins/` (e.g. `reverb.gfpd`).
2. Change the `id` to a unique reverse-DNS name (`com.yourname.yourplugin`).
3. Change `name`, `version`, and `type`.
4. Adjust the `parameters`, `graph`, and `ui` sections.
5. Place the file in `assets/plugins/` and add it to `pubspec.yaml` assets (the directory is already registered).
6. Call `GFDescriptorLoader.loadAndRegister(yamlString)` at startup.

GrooveForge automatically creates the plugin and registers it in the rack.

---

## File Format Reference

A `.gfpd` file is a YAML document with four top-level sections.

### 1. Metadata

```yaml
spec: "1.0"                          # always "1.0" for this version
id: "com.yourname.myreverb"          # globally unique, stable ID
name: "My Reverb"                    # display name in the rack
version: "1.0.0"                     # semantic version
type: effect                         # effect | instrument | midifx | analyzer
```

**Rules:**
- `id` must be globally unique across all installed plugins. Use reverse-DNS notation.
- `id` must never change once you publish the plugin — it is the key used to restore saved projects.
- `version` follows [semver](https://semver.org/).
- `type` determines which rack slots accept the plugin and which audio ports it has.

---

### 2. Parameters

Parameters are the knobs, toggles, and selectors the user controls.

```yaml
parameters:
  - id: mix           # internal key — used in graph bindings and UI controls
    paramId: 0        # integer index for get/setParameter (must be unique)
    name: "Mix"       # label shown in the auto-generated UI
    min: 0.0          # minimum raw value
    max: 100.0        # maximum raw value
    default: 50.0     # initial value (must be in [min, max])
    unit: "%"         # optional unit string displayed in tooltips

  - id: bpm_sync
    paramId: 1
    name: "BPM Sync"
    min: 0.0
    max: 1.0
    default: 0.0
    type: toggle      # float (default) | toggle | selector

  - id: waveform
    paramId: 2
    name: "Waveform"
    min: 0.0
    max: 2.0
    default: 0.0
    type: selector
    options: ["Sine", "Triangle", "Saw"]   # labels for each integer index
```

**Parameter types:**

| Type       | UI control | Value meaning                              |
|-----------|-----------|---------------------------------------------|
| `float`   | Knob/Slider| Continuous value in `[min, max]`           |
| `toggle`  | LED button | `0.0` = off, `1.0` = on                    |
| `selector`| Segmented  | Integer index 0…N-1 into `options` list    |

**Important:** `paramId` integers are stored in `.gf` project files. Never reorder or reuse them across versions — doing so would corrupt saved projects. Always add new parameters with new `paramId` values at the end.

---

### 3. DSP Graph

The graph describes which processing nodes to use and how audio flows between them.

```yaml
graph:
  nodes:
    - id: in        type: audio_in        # always required — the plugin's input
    - id: reverb    type: freeverb        # the processing node
      params:
        roomSize: { param: room_size }    # bind to plugin parameter
        damping:  { param: damping }
        width:    { value: 1.0 }          # constant — never changes
    - id: blend     type: wet_dry
      params:
        mix: { param: mix }
    - id: out       type: audio_out       # always required — the plugin's output

  connections:
    - from: in.out     to: [reverb.in, blend.dry]   # "to" can be a list
    - from: reverb.out to: blend.wet
    - from: blend.out  to: out.in
```

#### Node parameter bindings

Each node has internal parameters (specific to its algorithm). Bind them to your plugin parameters with `{ param: id }` or set a constant with `{ value: number }`.

- `{ param: room_size }` — follows the plugin parameter named `room_size`.
- `{ value: 0.5 }` — baked-in constant, set once at load time, never updated by the UI.

#### Connection syntax

```yaml
- from: nodeId.portName   to: targetNode.portName
- from: nodeId.portName   to: [target1.port, target2.port]
```

Port names per node type are listed below. If you omit the port name, `out` is assumed for `from` and `in` for `to`.

---

### 4. Built-in Node Library

These are all the processing nodes available in the current release.

#### `audio_in` / `audio_out`
Reserved — must appear exactly once in every graph. They connect the plugin to the host audio bus.

| Node       | Ports | Description                          |
|-----------|-------|--------------------------------------|
| `audio_in` | out   | Plugin input (L+R stereo)            |
| `audio_out`| in    | Plugin output (L+R stereo)           |

---

#### `gain`
Simple linear gain multiplier. Useful before or after other nodes.

| Node param | Raw range | Description           |
|-----------|----------|-----------------------|
| `gain`    | 0.0–2.0  | Multiplier (1.0=unity)|

---

#### `wet_dry`
Blends two signals. Essential for insert-effect mixing.

| Node param | Raw range | Description           |
|-----------|----------|-----------------------|
| `mix`     | 0.0–1.0  | 0=fully dry, 1=fully wet|

| Input port | Meaning                        |
|-----------|--------------------------------|
| `wet`     | Processed/effected signal       |
| `dry`     | Original/bypass signal          |

---

#### `freeverb`
Schroeder/Freeverb stereo plate reverb. Pure Dart, works on all platforms.

| Node param  | Raw range | Description                     |
|------------|----------|---------------------------------|
| `roomSize` | 0.0–1.0  | Room size / tail length         |
| `damping`  | 0.0–1.0  | High-frequency absorption       |
| `width`    | 0.0–1.0  | Stereo width (0=mono, 1=full)   |

---

#### `biquad_filter`
Standard second-order IIR filter (Audio EQ Cookbook). Modes:

| Mode index | Name        | Typical use                   |
|-----------|-------------|-------------------------------|
| 0         | Low-pass    | Remove highs                  |
| 1         | High-pass   | Remove lows                   |
| 2         | Band-pass   | Narrow frequency selection    |
| 3         | Notch       | Remove a specific frequency   |
| 4         | Peaking EQ  | Boost/cut a frequency band    |
| 5         | Low shelf   | Broad bass boost/cut          |
| 6         | High shelf  | Broad treble boost/cut        |

| Node param | Raw range      | Description                      |
|-----------|---------------|----------------------------------|
| `freq`    | 20–20000 Hz   | Corner/centre frequency          |
| `q`       | 0.1–20.0      | Quality factor / bandwidth       |
| `gain`    | -24–+24 dB    | Boost/cut (peaking/shelf modes)  |
| `mode`    | 0–6           | Filter mode (see table above)    |

Set `mode` as a constant binding using a fractional index: `{ value: 0.667 }` → mode 4 (peaking).

---

#### `delay`
Stereo ping-pong delay with optional BPM sync.

| Node param  | Raw range    | Description                          |
|------------|-------------|--------------------------------------|
| `timeMs`   | 1–2000 ms   | Delay time (when BPM sync is off)    |
| `feedback` | 0.0–0.99    | Echo decay factor                    |
| `bpmSync`  | 0/1         | Enable BPM sync (1=on)               |
| `beatDiv`  | 0–5 index   | Beat division: 0=2bars…5=1/16        |

---

#### `wah_filter`
Chamberlin SVF bandpass filter with internal BPM-syncable LFO.

| Node param   | Raw range    | Description                            |
|-------------|-------------|----------------------------------------|
| `center`    | 200–4000 Hz  | Sweep centre frequency                 |
| `resonance` | 0.5–20.0     | Q / resonance (higher = sharper)       |
| `rate`      | 0.1–10.0 Hz  | LFO rate (BPM sync off)                |
| `depth`     | 0.0–1.0      | LFO depth (sweep range)                |
| `waveform`  | 0–2          | 0=sine, 1=triangle, 2=sawtooth         |
| `bpmSync`   | 0/1          | Enable BPM sync (1=on)                 |
| `beatDiv`   | 0–5 index    | Beat division (same as delay)          |

---

#### `compressor`
RMS dynamics compressor with attack/release envelope.

| Node param   | Raw range      | Description                          |
|-------------|---------------|--------------------------------------|
| `threshold` | -60–0 dB      | Level above which compression starts |
| `ratio`     | 1.0–20.0      | Compression ratio (x:1)              |
| `attack`    | 0.1–200 ms    | How fast compression kicks in        |
| `release`   | 10–2000 ms    | How fast it lets go                  |
| `makeup`    | 0–24 dB       | Post-compression makeup gain         |

---

#### `chorus`
Stereo chorus / flanger with BPM-syncable rate.

| Node param   | Raw range    | Description                          |
|-------------|-------------|--------------------------------------|
| `rate`      | 0.1–10.0 Hz  | LFO modulation rate                  |
| `depth`     | 0.0–1.0      | Modulation depth                     |
| `delay`     | 5–50 ms      | Centre delay time                    |
| `feedback`  | 0.0–0.9      | Resonance / flanger feedback         |
| `bpmSync`   | 0/1          | Enable BPM sync                      |
| `beatDiv`   | 0–5 index    | Beat division                        |
| `mix`       | 0.0–1.0      | Dry/wet blend                        |

---

### 5. UI Layout

The `ui:` section describes which controls appear in the rack slot panel.

```yaml
ui:
  layout: row    # row (default) | grid

  controls:
    - type: knob      param: room_size               # rotary knob
    - type: slider    param: low_gain                # vertical fader
    - type: toggle    param: bpm_sync  label: "BPM"  # LED toggle button
    - type: selector  param: waveform  label: "Wave" # segmented selector
    - type: vumeter   source: out                     # stereo VU meter
    - type: button    action: reset    label: "Flat"  # action button
```

#### Control types

| Type       | Required fields    | Optional fields                  | Description                     |
|-----------|--------------------|----------------------------------|---------------------------------|
| `knob`    | `param`            | `label`, `size`                  | Rotary knob (standard control)  |
| `slider`  | `param`            | `label`, `size`                  | Vertical fader                  |
| `toggle`  | `param`            | `label`, `size`                  | Illuminated LED toggle          |
| `selector`| `param`            | `label`, `size`                  | Segmented option picker         |
| `vumeter` | `source` (node id) | `size`                           | Animated stereo level meter     |
| `button`  | `action`           | `label`, `size`                  | Momentary push button           |

#### Size hints

| Value    | Description                                |
|---------|--------------------------------------------|
| `small` | Compact — for secondary controls or grids  |
| `medium`| Default — standard rack-panel size         |
| `large` | Prominent — for the most important control |

#### Built-in actions (for `type: button`)

| Action  | Description                                      |
|--------|--------------------------------------------------|
| `reset` | Restores all parameters to their default values |

---

## Loading a Plugin at Runtime

Users can load `.gfpd` files from their device storage without rebuilding the app:

```dart
// Pick a .gfpd file using file_picker, then:
final content = await File(pickedPath).readAsString();
final plugin = GFDescriptorLoader.loadAndRegister(content);
if (plugin != null) {
  // Plugin is now available in AddPluginSheet.
}
```

---

## Common Recipes

### Basic insert effect (bypass-able)

```yaml
graph:
  nodes:
    - id: in      type: audio_in
    - id: effect  type: freeverb   # replace with any effect node
    - id: blend   type: wet_dry
      params:
        mix: { param: mix }
    - id: out     type: audio_out
  connections:
    - from: in.out     to: [effect.in, blend.dry]
    - from: effect.out to: blend.wet
    - from: blend.out  to: out.in
```

### Two effects in series

```yaml
graph:
  nodes:
    - id: in    type: audio_in
    - id: comp  type: compressor
    - id: rev   type: freeverb
    - id: out   type: audio_out
  connections:
    - from: in.out   to: comp.in
    - from: comp.out to: rev.in
    - from: rev.out  to: out.in
```

### BPM-synced wah (metronome locked)

```yaml
parameters:
  - id: bpm_on  paramId: 0  name: "Sync"  min: 0.0  max: 1.0  default: 1.0  type: toggle
  - id: div     paramId: 1  name: "Div"   min: 0.0  max: 5.0  default: 3.0  type: selector
    options: ["2 bars", "1 bar", "1/2", "1/4", "1/8", "1/16"]

graph:
  nodes:
    - id: in   type: audio_in
    - id: wah  type: wah_filter
      params:
        bpmSync: { param: bpm_on }
        beatDiv: { param: div }
        depth:   { value: 0.8 }      # fixed depth
        resonance: { value: 5.0 }    # fixed Q (raw — not normalised for constants)
    - id: out  type: audio_out
  connections:
    - from: in.out  to: wah.in
    - from: wah.out to: out.in
```

> **Note on `{ value: N }` for constants**: the value is passed directly as the
> normalised [0–1] argument to the node's `setParam`. For example, `resonance`
> on `wah_filter` maps 0→1 to 0.5→20.0, so `{ value: 0.23 }` ≈ Q 5.0.
> Use a plugin parameter with a constant default if you need raw units.

---

## Plugin ID Conventions

| Prefix | Meaning |
|--------|---------|
| `com.grooveforge.*` | Built-in GrooveForge plugins — do not use |
| `com.yourcompany.*` | Your organisation's plugins |
| `io.github.username.*` | Open-source plugins on GitHub |
| `com.example.*` | Prototyping only — never publish with this prefix |

---

## Checklist Before Publishing

- [ ] `id` is unique, stable, and follows reverse-DNS notation.
- [ ] `paramId` values are sequential, never reused, never reordered.
- [ ] All `default` values lie within `[min, max]`.
- [ ] Graph has exactly one `audio_in` and one `audio_out` node.
- [ ] Every `param` reference in the graph has a matching entry in `parameters`.
- [ ] Every `param` in the UI has a matching entry in `parameters`.
- [ ] The plugin sounds correct at 44100 Hz and 48000 Hz.
- [ ] Tested with BPM sync on and off (if applicable).

---

*GrooveForge Plugin API v1.0 — `.gfpd` spec v1.0*
