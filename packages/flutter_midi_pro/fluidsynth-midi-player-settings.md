MIDI player settings

player.reset-synth
Type
Boolean (int)
Values
0, 1
Default
1 (TRUE)
Real-time
This setting can be changed during runtime of the synthesizer.
If true, reset the synth after the end of a MIDI song, so that the state of a previous song can't affect the next song. Turn it off for seamless looping of a song.

player.timing-source
Type
Selection (str)
Options
sample, system
Default
sample
Determines the timing source of the player sequencer. 'sample' uses the sample clock (how much audio has been output) to sequence events, in which case audio is synchronized with MIDI events. 'system' uses the system clock, audio and MIDI are not synchronized exactly.
