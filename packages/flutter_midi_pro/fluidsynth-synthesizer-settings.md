Synthesizer settings

synth.audio-channels
Type
Integer (int)
Min - Max
1 - 128
Default
1
By default, the synthesizer outputs a single stereo signal. Using this option, the synthesizer can output multi-channel audio. Sets the number of stereo channel pairs. So 1 is actually 2 channels (a stereo pair).

synth.audio-groups
Type
Integer (int)
Min - Max
1 - 128
Default
1
The output audio channel associated with a MIDI channel is wrapped around using the number of synth.audio-groups as modulo divider. This is typically the number of output channels on the sound card, as long as the LADSPA Fx unit is not used. In case of LADSPA unit, think of it as subgroups on a mixer.

synth.chorus.active
Type
Boolean (int)
Values
0, 1
Default
1 (TRUE)
Real-time
This setting can be changed during runtime of the synthesizer.
When set to 1 (TRUE) the chorus effects module is activated. Otherwise, no chorus will be added to the output signal. Note that the amount of signal sent to the chorus module depends on the "chorus send" generator defined in the SoundFont.

synth.chorus.depth
Type
Float (num)
Min - Max
0.0 - 256.0
Default
4.25 (since version 2.4.0),
8.0 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Specifies the modulation depth of the chorus.

synth.chorus.level
Type
Float (num)
Min - Max
0.0 - 10.0
Default
0.6 (since version 2.4.0),
2.0 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Specifies the output amplitude of the chorus signal.

synth.chorus.nr
Type
Integer (int)
Min - Max
0 - 99
Default
3
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the voice count of the chorus.

synth.chorus.speed
Type
Float (num)
Min - Max
0.1 - 5.0
Default
0.2 (since version 2.4.0),
0.3 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the modulation speed in Hz.

synth.cpu-cores
Type
Integer (int)
Min - Max
1 - 256
Default
1
Sets the number of synthesis CPU cores. If set to a value greater than 1, additional synthesis threads will be created to do the actual rendering work that is then returned synchronously by the render function. This has the affect of utilizing more of the total CPU for voices or decreasing render times when synthesizing audio. So for example, if you set cpu-cores to 4, fluidsynth will attempt to split the synthesis work it needs to do between the client's calling thread and three additional (internal) worker threads. As soon as all threads have done their work, their results are collected and the resulting buffer is returned to the caller.

synth.default-soundfont
Type
String (str)
Default
C:\soundfonts\default.sf2 (Windows),
${CMAKE_INSTALL_PREFIX}/share/soundfonts/default.sf2 (all others)
The default soundfont file to use by the fluidsynth executable. The default value can be overridden during compilation time by setting the DEFAULT_SOUNDFONT cmake variable.

synth.device-id
Type
Integer (int)
Min - Max
0 - 127
Default
0
Real-time
This setting can be changed during runtime of the synthesizer.
Device identifier used for SYSEX commands, such as MIDI Tuning Standard commands. Fluidsynth will only process those SYSEX commands destined for this ID (except when this setting is set to 127, which causes fluidsynth to process all SYSEX commands, regardless of the device ID). Broadcast commands (with ID=127) will always be processed. It has been observed that setting this ID to 16 provides best compatibility when playing MIDI files which contain SYSEX commands that you want to have honored.

synth.dynamic-sample-loading
Type
Boolean (int)
Values
0, 1
Default
0 (FALSE)
When set to 1 (TRUE), samples are loaded to and unloaded from memory whenever presets are being selected or unselected for a MIDI channel (PROGRAM_CHANGE and PROGRAM_SELECT events are typically responsible for this). This involves memory allocation, which is not realtime safe! So only enable this in non-realtime scenarios! E.g. when rendering to a WAVE file using the fast-file-renderer.

synth.effects-channels
Type
Integer (int)
Min - Max
2 - 2
Default
2
Specifies the number of effects per effects group. Currently this value can not be changed so there are always two effects per group available (reverb and chorus).

synth.effects-groups
Type
Integer (int)
Min - Max
1 - 128
Default
1
Specifies the number of effects groups. By default, the sound of all voices is rendered by one reverb and one chorus effect respectively (even for multi-channel rendering). This setting gives the user control which effects of a voice to render to which independent audio channels. E.g. setting synth.effects-groups == synth.midi-channels allows to render the effects of each MIDI channel to separate audio buffers. If synth.effects-groups is smaller than the number of MIDI channels, it will wrap around. Note that any value >1 will significantly increase CPU usage.

synth.gain
Type
Float (num)
Min - Max
0.0 - 10.0
Default
0.2
Real-time
This setting can be changed during runtime of the synthesizer.
The gain is applied to the final or master output of the synthesizer. It is set to a low value by default to avoid the saturation of the output when many notes are played.

synth.ladspa.active
Type
Boolean (int)
Values
0, 1
Default
0 (FALSE)
When set to 1 (TRUE) the LADSPA subsystem will be enabled. This subsystem allows to load and interconnect LADSPA plug-ins. The output of the synthesizer is processed by the LADSPA subsystem. Note that the synthesizer has to be compiled with LADSPA support. More information about the LADSPA subsystem can be found in doc/ladspa.md or on the FluidSynth website.

synth.lock-memory
Type
Boolean (int)
Values
0, 1
Default
1 (TRUE)
Page-lock memory that contains audio sample data, if true.

synth.midi-channels
Type
Integer (int)
Min - Max
16 - 256
Default
16
This setting defines the number of MIDI channels of the synthesizer. The MIDI standard defines 16 channels, so MIDI hardware is limited to this number. Internally FluidSynth can use more channels which can be mapped to different MIDI sources.

synth.midi-bank-select
Type
Selection (str)
Options
gs, gm, xg, mma
Default
gs
This setting defines how the synthesizer interprets Bank Select messages.

gs: (default) CC0 becomes the bank number, CC32 is ignored.
gm: ignores CC0 and CC32 messages.
mma: bank is calculated as CC0\*128+CC32.
xg: If CC0 is equal to 120, 126, or 127 then channel is set to drum mode and the bank number is set to 128. CC32 is ignored in this case. If CC0 has a different value, the channel is set to melodic and CC32 becomes the bank number. Note that before fluidsynth 2.3.5 the logic for CC0 was broken.

synth.min-note-length
Type
Integer (int)
Min - Max
0 - 65535
Default
10
Sets the minimum note duration in milliseconds. This ensures that really short duration note events, such as percussion notes, have a better chance of sounding as intended. Set to 0 to disable this feature.

synth.note-cut
Type
Integer (int)
Min - Max
0 - 2
Default
0
This setting specifies the behavior for releasing voices, if the same note is hit twice on the same channel. Early synthesizers like the Roland SC-55 and Microsoft Wavetable GS MIDI synthesizer (MSGS) are terminating notes abruptly that have already received a noteOff after receiving a noteOn for the same key. This behavior was presumably implemented to save polyphony in these systems. This setting was introduced in fluidsynth 2.4.3 and can be enabled to mimic this behavior, to esp. play back old tunes like Doom E1M1 more accurately. Please note that using a SoundFont which makes proper use of exclusive classes for esp. percussion instruments will yield a similar or better result. Also, this approach is generally preferable because it's portable among SF2 compliant synths and can be applied more fine-grained among instruments. This setting supports the following values:

0: A regular noteOff is applied to the previous note, which is the default SF2 compliant behavior.
1: Note-cut is only applied on drum MIDI channels (i.e. CHANNEL_TYPE_DRUM). Fluidsynth 2.4.0, 2.4.1, and 2.4.2 unconditionally used this mode.
2: Note-cut is applied to both, drum and melodic MIDI channels (i.e. CHANNEL_TYPE_DRUM and CHANNEL_TYPE_MELODIC).

synth.overflow.age
Type
Float (num)
Min - Max
-10000.0 - 10000.0
Default
1000.0
Real-time
This setting can be changed during runtime of the synthesizer.
This score is divided by the number of seconds this voice has been active and is added to the overflow priority. It is usually a positive value and gives voices which have just been started a higher priority, making them less likely to be killed in an overflow situation.

synth.overflow.important
Type
Float (num)
Min - Max
-50000.0 - 50000.0
Default
5000.0
Real-time
This setting can be changed during runtime of the synthesizer.
This score is added to voices on channels marked with the synth.overflow.important-channels setting.

synth.overflow.important-channels
Type
String (str)
Default
(empty string)
Real-time
This setting can be changed during runtime of the synthesizer.
This setting is a comma-separated list of MIDI channel numbers that should be treated as "important" by the overflow calculation, adding the score set by synth.overflow.important to each voice on those channels. It can be used to make voices on particular MIDI channels less likely (synth.overflow.important > 0) or more likely (synth.overflow.important < 0) to be killed in an overflow situation. Channel numbers are 1-based, so the first MIDI channel is number 1.

synth.overflow.percussion
Type
Float (num)
Min - Max
-10000.0 - 10000.0
Default
4000.0
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the overflow priority score added to voices on a percussion channel. This is usually a positive score, to give percussion voices a higher priority and less chance of being killed in an overflow situation.

synth.overflow.released
Type
Float (num)
Min - Max
-10000.0 - 10000.0
Default
-2000.0
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the overflow priority score added to voices that have already received a note-off event. This is usually a negative score, to give released voices a lower priority so that they are killed first in an overflow situation.

synth.overflow.sustained
Type
Float (num)
Min - Max
-10000.0 - 10000.0
Default
-1000.0
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the overflow priority score added to voices that are currently sustained. With the default value, sustained voices are considered less important and are more likely to be killed in an overflow situation.

synth.overflow.volume
Type
Float (num)
Min - Max
-10000.0 - 10000.0
Default
500.0
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the overflow priority score added to voices based on their current volume. The voice volume is normalized to a value between 0 and 1 and multiplied with this setting. So voices with maximum volume get added the full score, voices with only half that volume get added half of this score.

synth.polyphony
Type
Integer (int)
Min - Max
1 - 65535
Default
256
Real-time
This setting can be changed during runtime of the synthesizer.
The polyphony defines how many voices can be played in parallel. A note event produces one or more voices. Its good to set this to a value which the system can handle and will thus limit FluidSynth's CPU usage. When FluidSynth runs out of voices it will begin terminating lower priority voices for new note events.

synth.reverb.active
Type
Boolean (int)
Values
0, 1
Default
1 (TRUE)
Real-time
This setting can be changed during runtime of the synthesizer.
When set to 1 (TRUE) the reverb effects module is activated. Otherwise, no reverb will be added to the output signal. Note that the amount of signal sent to the reverb module depends on the "reverb send" generator defined in the SoundFont.

synth.reverb.damp
Type
Float (num)
Min - Max
0.0 - 1.0
Default
0.3 (since version 2.4.0),
0.0 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the amount of reverb damping.

synth.reverb.level
Type
Float (num)
Min - Max
0.0 - 1.0
Default
0.7 (since version 2.4.0),
0.9 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the reverb output amplitude.

synth.reverb.room-size
Type
Float (num)
Min - Max
0.0 - 1.0
Default
0.5 (since version 2.4.0),
0.2 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the room size (i.e. amount of wet) reverb.

synth.reverb.width
Type
Float (num)
Min - Max
0.0 - 100.0
Default
0.8 (since version 2.4.0),
0.5 (2.3.x and older)
Real-time
This setting can be changed during runtime of the synthesizer.
Sets the stereo spread of the reverb signal. A value of 0 indicates no stereo-separation causing the reverb to sound like a monophonic signal. A value of 1 indicates maximum separation between the uncorrelated left and right channels (note that reverb is still a monophonic effect). This subrange [0;1] is recommended for general usage. Values bigger than 1 increase (or exaggerate) the perception of the uncorrelated left and right signals. Otherwise, this setting should be considered as dimensionless quantity, with its maximum value existing for historical reasons. Please note that under some circumstances, values bigger than 1 may induce a feedback into the signal which can be perceived as unpleasant.

synth.sample-rate
Type
Float (num)
Min - Max
8000.0 - 96000.0
Default
44100.0
The sample rate of the audio generated by the synthesizer. For optimal performance, make sure this value equals the native output rate of the audio driver (in case you are using any of fluidsynth's audio drivers). Some drivers, such as Oboe, will interpolate sample-rates, whereas others, such as Jack, will override this setting, if a mismatch with the native output rate is detected.

synth.threadsafe-api
Type
Boolean (int)
Values
0, 1
Default
1 (TRUE)
Controls whether the synth's public API is protected by a mutex or not. Default is on, turn it off for slightly better performance if you know you're only accessing the synth from one thread only, this could be the case in many embedded use cases for example. Note that libfluidsynth can use many threads by itself (shell is one, midi driver is one, midi player is one etc) so you should usually leave it on.

synth.verbose
Type
Boolean (int)
Values
0, 1
Default
0 (FALSE)
When set to 1 (TRUE) the synthesizer will print out information about the received MIDI events to the stdout. This can be helpful for debugging. This setting cannot be changed after the synthesizer has started.
