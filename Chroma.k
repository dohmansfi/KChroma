
#include "klang.h"
using namespace klang::optimised;

// cubic shaping function
static mono::signal cubed(mono::signal x) {
    return x * x * x;  // raises the input to the 3rd power.
}

// // non-linear exponential shaping
// static mono::signal nonlinear(mono::signal x) {
//     return pow(10, 2 * (x - 1));
// }

// linear mapping 0..1 to min..max
static param linearMap(param x, int min, int max) {
	return x * (max - min) + min;
}

// -- LFO --
struct LFO : Modifier {
	Sine sin;
	Triangle tri;
	Saw saw;
	LPF lpf;
	mono::signal lfo;
	
	/** SIGMOID BLENDING FUNCTION
		creates a smooth transition between waveforms based on a control parameter (`position`).
		`center` defines the midpoint of the transition, and `sharpness` defines how steep the transition is.
	*/
	mono::signal sigmoidBlend(param position, float center, float sharpness = 10.0) {
		return 1.0 / (1.0 + exp(-sharpness * (position - center)));
	}
	
	void set(param rate, param shape) {
		// compute blending weights for morphing
        mono::signal blend1 = sigmoidBlend(shape * 2, 0.5);  // sine to triangle
        mono::signal blend2 = sigmoidBlend(shape * 2, 1.5);  // triangle to saw
		
		// mod signals
        mono::signal sinMod = sin(rate) * 0.5 + 0.5;
        mono::signal triMod = tri(rate) * 0.5 + 0.5;
        mono::signal sawMod = saw(rate) * 0.5 + 0.5;
        mono::signal smoothSaw = sawMod >> lpf(500);  // smooth the saw wave to avoid clicks or harsh transitions
        lfo = (1.0 - blend1) * sinMod + (blend1 - blend2) * triMod + blend2 * smoothSaw;
	}
	
	void process() {
		lfo >> out;
	}
};

// -- FILTER --
struct CCF : Effect {
	HPF hpf;
	LPF lpf;
	BPF bpf;
	
	param f = 0;
	param q = 0;
	
	int mode = 0;
	
	void set(param frequency, param resonance, int hp, int lp) {
		f = linearMap(cubed(frequency), 100, 10000);
		if (f > 14000)  f = 14000;  // clamp frequency to a valid audio range
        if (f < 20)     f = 20;
            
		q = resonance;
		if (q > 2)  q = 2;  // clamp resonance to a usable range
        if (q < 0)  q = 0;
		
        if (hp && !lp)       mode = 1;  // high pass
        else if (!hp && lp)  mode = 2;  // low pass
        else if (hp && lp)   mode = 3;  // band pass
        else 			     mode = 0;  // bypass
	}
	
	void process() {
        if (mode == 1)		 in >> hpf(f, q) >> out;
        else if (mode == 2)  in >> lpf(f, q) >> out;
        else if (mode == 3)  in >> bpf(f, q) >> out;
        else				 in >> out;
	}
};

// -- FLANGER --
struct Flanger : Stereo::Effect {
	Stereo::Delay<192000> delay;
	Triangle lfo;
	mono::signal mod;
	
	void set(param rate, param depth) {
		mod = lfo(rate) * depth + depth;
	}

	void process() {
		// feed original and delayed signal with modulated delay time	
		in + (in >> delay)(mod * fs) >> out;
	}
};

// -- GLIMMER -- stereo chorus fx --
struct Glimmer : Stereo::Effect {
Delay<192000> gleam[4];  // four short delay lines (2 per channel)
Sine gleamMod[2];        // two LFOs to modulate each channel
param a;                 // modulation amount
param spread;            // spacing between delays

	mono::signal tap(Delay<192000>& buffer, mono::signal x, param time, param gain) {
		x >> buffer;
		return x + buffer(time * fs) * gain;
	}
	
	void set(param amount) {
		a = amount * 0.5;
		spread = 0.3 + (amount * 0.8);  // increase stereo spread based on amount
	}
	
	void process() {
		// LFO modulations for both channels
		mono::signal mod1 = gleamMod[0](a * 2, 0);
		mono::signal mod2 = gleamMod[1](a * 2, 0.25);
		
		// apply cross-feedback delays with subtle timing differences
		mono::signal left  = tap(gleam[0], in.l, (0.04 * spread) + mod1, a * 0.75)
                           - tap(gleam[1], in.r, (0.05 * spread) + mod2, a * 0.75);
        mono::signal right = tap(gleam[2], in.r, (0.03 * spread) + mod1, a * 0.75)
                           - tap(gleam[3], in.l, (0.06 * spread) + mod2, a * 0.75);
                     
        in.l + left >> out.l;
        in.r + right >> out.r;
	}
};

#define N_HARMONICS 16

// -- HARMONICS TABLES --
struct HarmonicsTable {
    float amplitude[N_HARMONICS];  // stores gain values for each harmonic
};

// -- OSCILLATOR --
struct ChromaOsc : Oscillator {
	Sine harmonic[N_HARMONICS];  // partials
	param gain[N_HARMONICS];     // amplitude per harmonics
	
	void set(param frequency) {
		for (int h = 0; h < N_HARMONICS; h++) {
			harmonic[h].set(frequency * (h + 1));
		}
	}
	
	// interpolates between the amplitudes in A and B based on morphAmount
	void morph(param morphAmount, HarmonicsTable& A, HarmonicsTable& B) {
        for (int h = 0; h < N_HARMONICS; h++) {
            gain[h] = A.amplitude[h] * (1.0 - morphAmount) + B.amplitude[h] * morphAmount;
        }
    }
	
	void process() {
    	for (int h = 0; h < N_HARMONICS; h++)
        	out += (harmonic[h] * gain[h]);
        	
        out *= 0.1;  // static output gain (headroom margin)
    }
};

// -- SYNTH --
struct Chroma : Stereo::Synth {
Flanger flanger;
Glimmer glimmer;
Stereo::Delay<192000> pingPong;
    
    HarmonicsTable tableA {  // saw wave (odd and even harmonics)
        { 1.0, 0.5, 0.333, 0.25, 0.2, 0.167, 0.143, 0.125,
          0.111, 0.1, 0.091, 0.083, 0.077, 0.071, 0.067, 0.063 }
    };

    HarmonicsTable tableB {  // square wave (odd harmonics)
        { 1.0, 0.0, 0.333, 0.0, 0.2, 0.0, 0.143, 0.0,
          0.111, 0.0, 0.091, 0.0, 0.077, 0.0, 0.067, 0.0 }
    };

    void getHarmonicTable(int bank /*0=A, 1=B*/, float* dest16) const noexcept
    {
        const HarmonicsTable& T = (bank == 0 ? tableA : tableB);
        for (int h = 0; h < N_HARMONICS; ++h)
            dest16[h] = T.amplitude[h];
    }
    
    void setHarmonicTable (int bank /*0=A,1=B*/, const float* src16) noexcept
    {
        HarmonicsTable& T = (bank == 0 ? tableA : tableB);
        for (int h = 0; h < N_HARMONICS; ++h)
            T.amplitude[h] = src16[h];
    }

	struct ChromaNote : public Mono::Note {
		ChromaOsc osc;
        ADSR adsr, mod;
        LFO lfo;
        CCF filter;

    	Chroma* chroma = nullptr;  // owning synth — set when klang attaches this note

    	void init() override { chroma = static_cast<Chroma*>(getSynth()); }

		event on(Pitch pitch, Amplitude velocity) {
			const param f = pitch -> Frequency;
			osc.set(f);
			adsr(controls[27] + 0.005, controls[27] + controls[28], controls[29], controls[30]);
			mod (controls[31] + 0.005, controls[31] + controls[32], controls[33], controls[34]);
		}

		event off(Amplitude velocity) {
			adsr.release();
		}

		// -- NOTE PROCESS() --
		void process() {
			// morph oscillator via LFO or ENV
			int morph = controls[2];
			if (morph)
				osc.morph(lfo * controls[3], chroma->tableA, chroma->tableB);
			if (!morph)
				osc.morph(mod * controls[3], chroma->tableA, chroma->tableB);
				
			// LFO settings
			lfo.set(controls[35] * 8, controls[36] * 2);
				
			// filter modulation via LFO or ENV
			int filterMod = controls[22];
			param cutoff = controls[23];
			param q = linearMap(controls[25], 0, 2);
			if (filterMod)
				filter.set(cutoff + lfo * controls[24], q + lfo * controls[26], controls[20], controls[21]);
			
			if (!filterMod)
				filter.set(cutoff + mod * controls[24], q + mod * controls[26], controls[20], controls[21]);
			
			osc * adsr >> filter >> out;
			
			if (adsr.finished())
				stop();
		}
	};
	
	// -- SYNTH PROCESS() --
	void process(){
		// reflect table values in the UI / update harmonic table from sliders
		int select = controls[0];  // 0 = tableA, 1 = tableB
		int edit = controls[1];
		for (int h = 0; h < N_HARMONICS; h++) {
			if (edit) {  // EDIT mode: read slider values and update the corresponding harmonic table
				if (!select) {
						tableA.amplitude[h] = controls[h + 4];
					} else {
						tableB.amplitude[h] = controls[h + 4];
					}
			} else {  // VIEW mode: update the sliders to reflect current values in the selected harmonic table
				!select ? tableA.amplitude[h] >> controls[h + 4] : tableB.amplitude[h] >> controls[h + 4];
			}	
		}

		// FX chain
		stereo::signal wet = in;
		
		int flange = controls[37];
		if (flange) {  // flanger
			flanger.set(controls[38], controls[39] / 1000.f);
			wet * 0.75 >> flanger >> wet;
		}
		
		int gleam = controls[40];
		if (gleam) {  // glimmer
			glimmer.set(controls[41]);
			wet * 0.75 >> glimmer >> wet;
		}
		
		int delay = controls[42];
		if (delay) {  // ping-pong delay
			stereo::signal time = { controls[43].smooth(), controls[44].smooth() };
			stereo::signal gain = { controls[45], controls[45] };
			param amount = controls[46].smooth() * 0.8;
			wet + pingPong(time * fs) * gain * amount >> wet;
			pingPong.l << wet.r;
			pingPong.r << wet.l;
		}
		
		// out
		param mix = controls[47];
		param volume = controls[48];
		(wet * mix + in * (1 - mix)) * volume >> out;
	}

	Chroma() {
		controls = {
			/* OSCILLATOR */											  //    OSCILLATOR
                Menu   ("harmonics", { 15, 25, 45, 18 }, "A", "B"),  	  // 00 ├ HARMONICS TABLES
                Toggle ("edit", 0, { 66, 25, 18, 18 }),    			 	  // 01 │
                Menu   ("morph", { 15, 65, 45, 18 }, "env", "lfo"),  	  // 02 │
                Dial   ("morphAmount", 0, 1, 0, { 66, 65, 18, 18 }),      // 03 ├ morph amount
                Slider ("pOne",  0, 1, 0, { 90,  25, 10, 60 }),	          // 04 └ HARMONICS' AMPLITUDES
                Slider ("pTwo",  0, 1, 0, { 105, 25, 10, 60 }),	          // 05   │
                Slider ("pThree",  0, 1, 0, { 120, 25, 10, 60 }),	      // 06   │
                Slider ("pFour",  0, 1, 0, { 135, 25, 10, 60 }),	      // 07   │
                Slider ("pFive",  0, 1, 0, { 150, 25, 10, 60 }),	      // 08   │
                Slider ("pSix",  0, 1, 0, { 165, 25, 10, 60 }),	          // 09   │
                Slider ("pSeven",  0, 1, 0, { 180, 25, 10, 60 }),	      // 10   │
                Slider ("pEight",  0, 1, 0, { 195, 25, 10, 60 }),	      // 11   │
                Slider ("pNine",  0, 1, 0, { 210, 25, 10, 60 }),	      // 12   │
                Slider ("pTen", 0, 1, 0, { 225, 25, 10, 60 }),	          // 13   │
                Slider ("pEleven", 0, 1, 0, { 240, 25, 10, 60 }),	      // 14   │
                Slider ("pTwelve", 0, 1, 0, { 255, 25, 10, 60 }),	      // 15   │
                Slider ("pThirteen", 0, 1, 0, { 270, 25, 10, 60 }),       // 16   │
                Slider ("pFourteen", 0, 1, 0, { 285, 25, 10, 60 }),       // 17   │
                Slider ("pFifteen", 0, 1, 0, { 300, 25, 10, 60 }),        // 18   │
                Slider ("pSixteen", 0, 1, 0, { 315, 25, 10, 60 }),        // 19   └
					   	
			{ "FILTER",												 	  //    FILTER
                Toggle ("highPass", 0, { 341, 30, 18, 18 }),              // 20 │
                Toggle ("lowPass", 0, { 367, 30, 18, 18 }),               // 21 │
                Menu   ("filterMod", { 340, 70, 45, 18 }, "env", "lfo"),  // 22 │
                Dial   ("cutoff", 0, 1, 0, { 340, 110, 40, 40 }),  		  // 23 │
                Dial   ("cutoffMod", -1, 1, 0, { 369, 104, 18, 18 }),     // 24 ├ f mod amount
                Dial   ("q", 0, 1, 0, { 340, 170, 40, 40 }),    	 	  // 25 │
                Dial   ("qMod", -1, 1, 0, { 369, 164, 18, 18 }),    	  // 26 └ q mod amount
            },
                          
			{ "AMP ENV  /   MOD ENV",						 			  //    ENVELOPES
                Dial   ("attack", 0, 1, 0, { 15,  130, 40, 40 }),	 	  // 27 ├ AMP
                Dial   ("decay", 0.0, 1, 0.5, { 65,  130, 40, 40 }),	  // 28 │ │
                Dial   ("sustain", 0, 1, 0.75, { 115, 130, 40, 40 }),	  // 29 │ │
                Dial   ("release", 0, 1, 0.5, { 165, 130, 40, 40 }),   	  // 30 │ └
                Dial   ("modAttack", 0, 1, 0, { 44,  124, 18, 18 }),      // 31 └ MOD attack
                Dial   ("modDecay", 0.0, 1, 0, { 94, 124, 18, 18 }),      // 32   ├	 decay
                Dial   ("modSustain", 0, 1, 0, { 144, 124, 18, 18 }),     // 33   ├	 sustain
                Dial   ("modRelease", 0, 1, 0, { 194, 124, 18, 18 })      // 34   └	 release
            },
			
			{ "LFO",
                Dial   ("modRate",  0, 1, 0, { 231, 130, 40, 40 }),       // 35 LFO
                Dial   ("modShape", 0, 1, 0, { 281, 130, 40, 40 })        // 36 └
            },
					
			/* MIXER */													  //    EFFECTS
                Toggle ("flanger", 0, { 15, 185, 40, 18 }),          	  // 37 ├ FLANGER
                Dial   ("flangerRate", 0.1, 1, 0, { 65, 185, 18, 18 }),	  // 38 │ ├ rate
                Dial   ("flangerDepth", 0.1, 5, 0, { 88, 185, 18, 18 }),  // 39 │ └ depth
                Toggle ("glimmer", 0, { 15, 210, 40, 18 }),			 	  // 40 ├ GLIMMER
                Dial   ("glimmerAmount", 0.1, 1, 0, { 65, 210, 18, 18 }), // 41 │ └ amount
                Toggle ("delay", 0, { 115, 185, 40, 18 }),			 	  // 42 ├ DELAY
                Dial   ("delayTimeL", 0, 1, 0, { 165, 185, 18, 18 }),	  // 43 │ ├ time left
                Dial   ("delayTimeR", 0, 1, 0, { 188, 185, 18, 18 }),	  // 44 │ ├ time right
                Dial   ("delayFeedback", 0, 1, 0, { 165, 210, 18, 18 }),  // 45 │ ├ feedback
                Dial   ("delayGain", 0, 1, 0, { 188, 210, 18, 18 }),	  // 46 │ └ gain
                Dial   ("fx", 0, 1, 0, { 239, 205, 24, 23 }),		 	  // 47 └ DRY / WET
                Dial   ("volume", 0, 1.5, 1, { 289, 205, 24, 23 })	 	  // 48 OUT VOLUME
		};
		
		presets = {
			{ "Double Attack", { 1, 1, 1, 1.000, 1.000, 0.591, 0.600, 0.000, 0.000, 0.000, 0.200, 0.700, 0.100, 0.080, 0.070, 0.050, 0.040, 0.030, 0.020, 0.010, 0, 1, 0, 0.218, 0.818, 0.000, 0.308, 0.000, 0.348, 0.402, 0.207, 0.000, 0.200, 0.000, 0.000, 1.000, 1.000, 1, 0.447, 1.043, 1, 0.631, 0, 0.309, 0.310, 0.383, 1.000, 1.000, 1.000 } },
			{ "LPG-ish", { 1, 1, 0, 0.932, 1.000, 0.591, 0.600, 0.000, 0.000, 0.000, 0.200, 0.700, 0.100, 0.080, 0.070, 0.050, 0.040, 0.030, 0.020, 0.010, 0, 1, 0, 0.165, 0.741, 0.000, -0.571, 0.000, 0.000, 1.000, 0.487, 0.000, 0.000, 0.133, 0.286, 0.000, 0.000, 1, 0.100, 0.100, 0, 0.100, 1, 0.309, 0.310, 0.383, 1.000, 1.000, 1.000 } },
			{ "House Bass", { 0, 0, 0, 0.466, 1.000, 0.600, 0.000, 0.300, 0.000, 0.150, 0.000, 0.080, 0.060, 0.050, 0.040, 0.030, 0.020, 0.015, 0.010, 0.005, 0, 1, 0, 0.000, 0.530, 0.000, 0.000, 0.000, 0.500, 0.750, 0.500, 0.000, 0.555, 0.411, 0.414, 0.000, 0.000, 0, 0.100, 0.100, 1, 0.535, 0, 0.622, 0.770, 0.500, 0.866, 0.447, 1.000 } },
			{ "Subtractive Synth", { 0, 0, 0, 1.000, 1.000, 0.500, 0.333, 0.250, 0.200, 0.167, 0.143, 0.125, 0.111, 0.100, 0.091, 0.083, 0.077, 0.071, 0.067, 0.063, 0, 1, 0, 0.286, 1.000, 0.000, 0.000, 0.000, 0.766, 0.838, 0.786, 0.000, 0.670, 0.080, 0.365, 0.000, 0.000, 1, 0.533, 2.503, 1, 0.585, 1, 0.398, 0.510, 0.505, 0.500, 0.845, 1.000 } },
			{ "Faux Delay", { 1, 0, 0, 1.000, 1.000, 0.000, 0.333, 0.000, 0.200, 0.000, 0.143, 0.000, 0.111, 0.000, 0.091, 0.000, 0.077, 0.000, 0.067, 0.000, 0, 1, 1, 0.043, 1.000, 0.000, 1.000, 0.000, 0.766, 0.838, 0.895, 0.000, 0.089, 0.080, 0.365, 1.000, 1.000, 1, 0.533, 2.503, 1, 1.000, 0, 0.398, 0.510, 0.505, 0.000, 0.845, 1.000 } },
		};
		notes.add<ChromaNote>(32);
	}
};
