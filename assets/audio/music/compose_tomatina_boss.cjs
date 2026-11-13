// Original composition: "El Rey del Tomate". 128 BPM, A minor / Phrygian,
// 32 bars, four 8-bar sections. All instruments synthesized here; no samples.
const fs = require('fs');
const path = require('path');
const SR = 44100, BPM = 144, BEAT = 60/BPM, BARS = 32;
const N = Math.round(SR*BEAT*4*BARS);
const left = new Float32Array(N), right = new Float32Array(N);
let seed=1847;
const random = () => { seed=(Math.imul(seed,1664525)+1013904223)>>>0; return seed/4294967296; };
const hz = n => 440*Math.pow(2,(n-69)/12);
const tables = new Map();
function table(kind) {
  if(tables.has(kind)) return tables.get(kind);
  const a=new Float32Array(4096);
  for(let i=0;i<a.length;i++) {
    const phase=i/a.length*Math.PI*2;
    let sum=0;
    const harmonics=kind==='guitar'?12:kind==='brass'?16:kind==='accordion'?12:6;
    for(let h=1;h<=harmonics;h++) {
      let w;
      if(kind==='guitar') w=Math.pow(h,-1.65)*(h%3===0?0.5:1);
      else if(kind==='brass') w=Math.pow(h,-1.25)*(0.6+Math.exp(-Math.pow((h-4)/3,2))*0.5);
      else if(kind==='accordion') w=(h%2?1:0.45)*Math.pow(h,-1.4);
      else w=Math.pow(h,-2.1);
      sum+=Math.sin(phase*h)*w;
    }
    a[i]=sum;
  }
  const peak=Math.max(...a.map(Math.abs));
  for(let i=0;i<a.length;i++) a[i]/=peak;
  tables.set(kind,a); return a;
}
function note(kind,midi,beat,duration,amp,pan=0) {
  const start=Math.round(beat*BEAT*SR);
  const seconds=duration*BEAT;
  const release=kind==='guitar'?0.25:0.08;
  const samples=Math.floor((seconds+release)*SR);
  const wave=table(kind), freq=hz(midi);
  const gl=Math.sqrt((1-pan)/2), gr=Math.sqrt((1+pan)/2);
  let phase=0;
  const detune=kind==='accordion'?0.003:0;
  for(let i=0;i<samples;i++) {
    const t=i/SR;
    const attack=Math.min(1,t/(kind==='brass'?0.022:0.006));
    let env;
    if(kind==='guitar') env=attack*Math.exp(-t/(0.16+seconds*0.6))*Math.max(0,1-t/(seconds+release));
    else env=attack*(t<seconds?1:Math.max(0,1-(t-seconds)/release));
    const vibrato=kind==='brass' && t>0.12?Math.sin(t*34)*0.003:0;
    const scoop=kind==='brass'?1-0.035*Math.exp(-t*65):1;
    phase+=freq*scoop*(1+vibrato)/SR;
    let sig=wave[(Math.floor(phase*4096))&4095];
    if(detune) sig=(sig+wave[(Math.floor(phase*(1+detune)*4096))&4095])*0.5;
    if(kind==='brass') sig=0.8*sig+0.2*Math.sin(phase*2*Math.PI);
    const index=(start+i)%N;
    left[index]+=sig*env*amp*gl; right[index]+=sig*env*amp*gr;
  }
}
function percussion(kind,beat,amp=0.2,pan=0) {
  const length=kind==='kick'?0.25:kind==='clap'?0.16:kind==='snare'?0.16:0.09;
  const start=Math.round(beat*BEAT*SR), gl=Math.sqrt((1-pan)/2), gr=Math.sqrt((1+pan)/2);
  let phase=0, previous=0;
  for(let i=0;i<length*SR;i++) {
    const t=i/SR, noise=random()*2-1;
    let sig=0;
    if(kind==='kick') { phase+=2*Math.PI*(52+90*Math.exp(-t*50))/SR; sig=Math.sin(phase)*Math.exp(-t*19); }
    else if(kind==='clap') { const burst=t<0.035?(Math.floor(t/0.008)%2===0?1:0.2):Math.exp(-(t-0.035)*37); sig=(noise-previous)*0.5*burst; }
    else if(kind==='castanet') sig=(Math.sin(2*Math.PI*1720*t)+Math.sin(2*Math.PI*2440*t)*0.5+noise*0.3)*Math.exp(-t*95);
    else if(kind==='snare') sig=(noise*0.7+Math.sin(2*Math.PI*175*t)*0.3)*Math.exp(-t*33);
    else sig=(noise-previous)*Math.exp(-t*80)*0.5;
    previous=noise;
    const index=(start+i)%N;
    left[index]+=sig*amp*gl; right[index]+=sig*amp*gr;
  }
}
// Original boss score: E Phrygian dominant, heavy 3+3+2 ostinato.
const chords=[[52,56,59,64],[53,57,60,65],[50,53,57,62],[52,56,59,64],
 [57,60,64,69],[55,59,62,67],[53,57,60,65],[52,56,59,64]];
const hooks=[
 [[0,64,.65],[.75,65,.2],[1.5,68,.4],[2.25,71,.4],[3,68,.35],[3.5,65,.2]],
 [[0,65,.6],[1,69,.35],[1.75,72,.35],[2.5,71,.35],[3.25,69,.35]],
 [[0,69,.4],[.75,65,.35],[1.5,62,.6],[2.5,65,.35],[3.25,64,.5]],
 [[0,68,.5],[.75,65,.25],[1.5,64,.5],[2.5,59,.4],[3.25,64,.5]],
 [[0,76,.65],[1,72,.3],[1.75,69,.4],[2.5,72,.3],[3.25,74,.35]],
 [[0,74,.5],[.75,71,.35],[1.5,67,.5],[2.5,71,.35],[3.25,72,.4]],
 [[0,72,.5],[.75,69,.25],[1.5,65,.5],[2.25,69,.35],[3,65,.6]],
 [[0,68,.5],[.75,71,.3],[1.5,76,.5],[2.5,77,.25],[3,76,.25],[3.5,68,.3]]];
for(let bar=0;bar<BARS;bar++) {
 const base=bar*4, chord=chords[bar%8], section=Math.floor(bar/8);
 for(const offset of [0,.75,1.5,2,2.75,3.5]) {
   note('bass',chord[0]-12,base+offset,.24,.33,-.05);
   note('brass',chord[0],base+offset,.15,.14,-.25);
 }
 for(const offset of [.5,1.25,2.5,3.25])
   chord.forEach((n,i)=>note('guitar',n,base+offset+i*.012,.25,.13,-.4));
 for(const offset of [0,1.5,2,3.5]) percussion('kick',base+offset,.39);
 for(const offset of [1,3]) {percussion('snare',base+offset,.23);percussion('clap',base+offset,.15,.25);}
 for(let i=0;i<16;i++) percussion(i%3===0?'castanet':'hat',base+i*.25,i%3===0?.07:.04,i%2?-.5:.5);
 for(const [offset,pitch,dur] of hooks[bar%8]) {
   note('brass',pitch,base+offset,dur,.27,.13);
   if(section===1 || section===3) note('brass',pitch-12,base+offset,dur,.13,-.12);
   if(section===2) note('accordion',pitch-12,base+offset+.125,dur*.6,.12,-.3);
 }
 if(bar%4===3) for(let i=0;i<6;i++) percussion('snare',base+2.5+i*.25,.13+i*.012);
}
// Short circular room reflections carry the last bar naturally into bar one.
for(const [delay,gain,cross] of [[.071,.13,true],[.113,.10,false],[.173,.07,true]]) {
  const d=Math.round(delay*SR);
  const srcL=left.slice(),srcR=right.slice();
  for(let i=0;i<N;i++) {const j=(i-d+N)%N;left[i]+=(cross?srcR[j]:srcL[j])*gain;right[i]+=(cross?srcL[j]:srcR[j])*gain;}
}
let peak=0, sum=0;
for(let i=0;i<N;i++) {left[i]=Math.tanh(left[i]*1.15);right[i]=Math.tanh(right[i]*1.15);peak=Math.max(peak,Math.abs(left[i]),Math.abs(right[i]));sum+=left[i]*left[i]+right[i]*right[i];}
const gain=.86/peak;
const data=Buffer.alloc(N*4+44);
data.write('RIFF',0);data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(2,22);data.writeUInt32LE(SR,24);data.writeUInt32LE(SR*4,28);data.writeUInt16LE(4,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(N*4,40);
for(let i=0;i<N;i++) {data.writeInt16LE(Math.round(left[i]*gain*32767),44+i*4);data.writeInt16LE(Math.round(right[i]*gain*32767),46+i*4);}
fs.writeFileSync(path.join(__dirname,'tomatina_boss.wav'),data);
console.log(JSON.stringify({title:'El Rey del Tomate',bpm:BPM,bars:BARS,seconds:N/SR,peak_db:20*Math.log10(.86),rms_db:20*Math.log10(Math.sqrt(sum/(2*N))*gain),original_synthesis:true}));
