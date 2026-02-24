Audio driver settings

audio.driver
Type
Selection (str)
Options
alsa, coreaudio, dart, dsound, file, jack, oboe, opensles, oss, portaudio, pulseaudio, sdl3, sndman, wasapi, waveout
Default
alsa (Linux),
dsound (Windows),
sndman (MacOS9),
coreaudio (Mac OS X),
dart (OS/2)
The audio system to be used. In order to use sdl3 as audio driver, the application is responsible for initializing SDL's audio subsystem.

Note: waveout is available since fluidsynth 2.1.0, sdl3 since fluidsynth 2.4.4.

audio.periods
Type
Integer (int)
Min - Max
2 - 64
Default
8 (Windows, MacOS9),
16 (all other)
The number of the audio buffers used by the driver. This number of buffers, multiplied by the buffer size (see setting audio.period-size), determines the maximum latency of the audio driver.

audio.period-size
Type
Integer (int)
Min - Max
64 - 8192
Default
512 (Windows),
64 (all other)
This is the number of audio samples most audio drivers will request from the synth at one time. In other words, it's the amount of samples the synth is allowed to render in one go when no state changes (events) are about to happen. Because of that, specifying too big numbers here may cause MIDI events to be poorly quantized (=untimed) when a MIDI driver or the synth's API directly is used, as fluidsynth cannot determine when those events are to arrive. This issue does not matter, when using the MIDI player or the MIDI sequencer, because in this case, fluidsynth does know when events will be received.

audio.realtime-prio
Type
Integer (int)
Min - Max
0 - 99
Default
60
Sets the realtime scheduling priority of the audio synthesis thread. This includes the synthesis threads created by the synth (in case synth.cpu-cores was greater 1). A value of 0 disables high priority scheduling. Linux is the only platform which currently makes use of different priority levels as specified by this setting. On other operating systems the thread priority is set to maximum. Drivers which use this option: alsa, oss and pulseaudio

audio.sample-format
Type
Selection (str)
Options
16bits, float
Default
16bits
The format of the audio samples. This is currently only an indication; the audio driver may ignore this setting if it can't handle the specified format.

audio.alsa.device
Type
Selection (str)
Options
ALSA device string, such as: "hw:0", "plughw:1", etc.
Default
default
Selects the ALSA audio device to use.

audio.coreaudio.device
Type
String (str)
Default
default
Selects the CoreAudio device to use.

audio.coreaudio.channel-map
Type
String (str)
Default
(empty string)
This setting is a comma-separated integer list that maps fluidsynth mono-channels to CoreAudio device output channels. Each position in the list represents the output channel of the CoreAudio device. The value of each position indicates the zero-based index of the fluidsynth output mono-channel to route there (i.e. the buffer index used for fluid_synth_process()). Additionally, the special value of -1 will turn off an output.

For example, the default map for a single stereo output is "0,1". A value of "0,0" will copy the left channel to the right, a value of "1,0" will flip left and right, and a value of "-1,1" will play only the right channel.

With a six-channel output device, and the synth.audio-channels and synth.audio-groups settings both set to "2", a channel map of "-1,-1,0,1,2,3" will result in notes from odd MIDI channels (audible on the first stereo channel, i.e. mono-indices 0,1) being sent to outputs 3 and 4, and even MIDI channels (audible on the second stereo channel, i.e. mono-indices 2,3) being sent to outputs 5 and 6.

If the list specifies less than the number of available outputs channels, outputs beyond those specified will maintain the default channel mapping given by the CoreAudio driver.

audio.dart.device
Type
String (str)
Default
default
Selects the Dart (OS/2 driver) device to use.

audio.dsound.device
Type
String (str)
Default
default
Selects the DirectSound (Windows) device to use. Starting with 2.3.6 all device names are expected to be UTF8 encoded.

audio.file.endian
Type
Selection (str)
Options
auto, big, cpu, little ('cpu' is all that is supported if libsndfile support is not built in)
Default
'auto' if libsndfile support is built in,
'cpu' otherwise.
Defines the byte order when using the 'file' driver or file renderer to store audio to a file. 'auto' uses the default for the given file type, 'cpu' uses the CPU byte order, 'big' uses big endian byte order and 'little' uses little endian byte order.

audio.file.format
Type
Selection (str)
Options
double, float, s16, s24, s32, s8, u8
Default
s16
Defines the audio format when rendering audio to a file. Limited to 's16' if no libsndfile support.

'double' is 64 bit floating point,
'float' is 32 bit floating point,
's16' is 16 bit signed PCM,
's24' is 24 bit signed PCM,
's32' is 32 bit signed PCM,
's8' is 8 bit signed PCM and
'u8' is 8 bit unsigned PCM.

audio.file.name
Type
String (str)
Default
'fluidsynth.wav' if libsndfile support is built in,
'fluidsynth.raw' otherwise.
Specifies the file name to store the audio to, when rendering audio to a file.

audio.file.type
Type
Selection (str)
Options
aiff, au, auto, avr, caf, flac, htk, iff, mat, oga, paf, pvf, raw, sd2, sds, sf, voc, w64, wav, xi
Default
'auto' if libsndfile support is built in,
'raw' otherwise.
Sets the file type of the file which the audio will be stored to. 'auto' attempts to determine the file type from the audio.file.name file extension and falls back to 'wav' if the extension doesn't match any types. Limited to 'raw' if compiled without libsndfile support. Actual options will vary depending on libsndfile library.

audio.jack.autoconnect
Type
Boolean (int)
Values
0, 1
Default
0 (FALSE)
If 1 (TRUE), then FluidSynth output is automatically connected to jack system audio output.

audio.jack.id
Type
String (str)
Default
fluidsynth
Unique identifier used when creating Jack client connection.

audio.jack.multi
Type
Boolean (int)
Values
0, 1
Default
0 (FALSE)
If 1 (TRUE), then multi-channel Jack output will be enabled if synth.audio-channels is greater than 1.

audio.jack.server
Type
String (str)
Default
(empty string)
Jack server to connect to. Defaults to an empty string, which uses default Jack server.

audio.oboe.id
Type
Integer (int)
Min - Max
0 - 2147483647
Default
0
Request an audio device identified device using an ID as pointed out by Oboe's documentation.

audio.oboe.sample-rate-conversion-quality
Type
Selection (str)
Options
None, Fastest, Low, Medium, High, Best
Default
None
Sets the sample-rate conversion quality as pointed out by Oboe's documentation.

audio.oboe.sharing-mode
Type
Selection (str)
Options
Shared, Exclusive
Default
Shared
Sets the sharing mode as pointed out by Oboe's documentation.

audio.oboe.performance-mode
Type
Selection (str)
Options
None, PowerSaving, LowLatency
Default
None
Sets the performance mode as pointed out by Oboe's documentation.

audio.oboe.error-recovery-mode
Type
Selection (str)
Options
Reconnect, Stop
Default
Reconnect
Sets the error recovery mode when audio device error such as earphone disconnection occurred. It reconnects by default (same as OpenSLES behavior), but can be stopped if Stop is specified.

audio.oss.device
Type
String (str)
Default
/dev/dsp
Device to use for OSS audio output.

audio.pipewire.media-category
Type
String (str)
Default
Playback
The media category to use. This value will be passed to PW_KEY_MEDIA_CATEGORY, see Pipewire documentation for valid values.

audio.pipewire.media-role
Type
String (str)
Default
Music
The media role to use. This value will be passed to PW_KEY_MEDIA_ROLE, see Pipewire documentation for valid values.

audio.pipewire.media-type
Type
String (str)
Default
Audio
The media type to use. This value will be passed to PW_KEY_MEDIA_TYPE, see Pipewire documentation for valid values.

audio.portaudio.device
Type
String (str)
Default
PortAudio Default
Device to use for PortAudio driver output. Note that 'PortAudio Default' is a special value which outputs to the default PortAudio device. The format of the device name is: "<device_index>:<host_api_name>:<host_device_name>" e.g. "11:Windows DirectSound:SB PCI"

audio.pulseaudio.adjust-latency
Type
Boolean (int)
Values
0, 1
Default
1 (TRUE)
If TRUE initializes the maximum length of the audio buffer to the highest supported value and increases the latency dynamically if PulseAudio suggests so. Else uses a buffer with length of "audio.period-size".

audio.pulseaudio.device
Type
String (str)
Default
default
Device to use for PulseAudio driver output.

audio.pulseaudio.media-role
Type
String (str)
Default
music
PulseAudio media role information.

audio.pulseaudio.server
Type
String (str)
Default
default
Server to use for PulseAudio driver output.

audio.sdl3.device
Type
String (str)
Default
default
Device to use for SDL3 driver output.

audio.wasapi.device
Type
String (str)
Default
default
Device to use for WASAPI driver output. Starting with 2.3.6 all device names are expected to be UTF8 encoded.

audio.wasapi.exclusive-mode
Type
Boolean (int)
Values
0, 1
Default
0 (FALSE)
By default, WASAPI will operate in shared mode. Set it to 1 (TRUE) to use WASAPI in exclusive mode. In this mode, you'll benefit from direct soundcard access via kernel streaming, which has an extremely low latency. However, you must pay close attention to other settings, such as synth.sample-rate and audio.sample-format as your soundcard may not accept any possible sample configuration.

audio.waveout.device
Type
String (str)
Default
default
Device to use for WaveOut driver output. Starting with 2.3.6 all device names are expected to be UTF8 encoded.
