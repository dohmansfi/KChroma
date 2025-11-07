# CHROMA SYNTH

### Overivew
Chroma is a stereo additive synthesiser that blends two user-defined harmonic spectra—Wave A and Wave B—using morphing techniques modulated by an LFO or envelope. The name Chroma references chromaticity: the progression from grayscale to full colour saturation. In this context, it symbolises the sonic transition between two spectral states, offering expressive control through harmonic interpolation. The name reflects both the spectral design and the aesthetic goal of enabling a dynamic timbral palette.

### Harmonic Oscillator
The synth uses 16 harmonics. Two independent harmonic tables (A and B) define the amplitude of each partial. By default, Table A is loaded with a saw wave (all harmonics), and Table B with a square wave (odd harmonics only). The user can select which table to edit using a menu and sliders. Morphing between tables is controlled by an LFO or an envelope.

### Filter
A custom filter section provides three selectable modes—high-pass, low-pass, and band-pass— using toggle controls. Both cutoff frequency and resonance (Q) can be modulated via envelope or LFO. Frequency modulation is shaped nonlinearly for improved control in the low-frequency range.

### Modulation
- The LFO can smoothly morph between sine, triangle, and saw wave shapes using a sigmoid blending function.
- Two independent ADSRs are used: one for amplitude, and one assignable to modulation targets such as the filter frequency and resonance or oscillator morphing.

### Effects
The synthesiser features three effects, controlled via toggles and dials:
- Flanger: classic delay-line flanger modulated by a triangle LFO.
- Glimmer: a custom chorus effect using four short delay lines with cross-feedback and LFO modulation for subtle stereo widening.
- Delay: Stereo ping-pong delay with time, feedback, and gain control.

### GUI controls
![GUI](https://github.com/dohmansfi/KChroma/blob/9a631947deebc5ae26bfba89b5029655f952c4bd/img/GUI.jpg)

1. Edit mode toggle
2. Table A / B selector
3. Oscillator mod source
4. Oscillator mod amount
5. Envelopes
6. Flanger - Rate
7. Flanger - On / Off
8. Glimmer - On / Off
9. Glimmer - Amount
10. Flanger - Depth
11. Delay - On / Off
12. Delay - Time (left channel)
13. Delay - Feedback
14. Delay - Gain
15. Delay - Time (right channel)
16. Dry / Wet
17. Out volume
18. LFO controls
19. Filter controls
20. Filter modulation source
21. Filter state switches
22. Selected harmonic table
