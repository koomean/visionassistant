/* LunaV motion identity. Existing brand artwork: Wachirawich Kripindakul.
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Render with Node.js, @napi-rs/canvas 1.1.0, and FFmpeg on PATH.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { once } = require('node:events');
const { createCanvas, GlobalFonts, Path2D } = require('@napi-rs/canvas');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'exports', 'v3');
const PREVIEW = path.join(ROOT, 'preview', 'v3');
fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(PREVIEW, { recursive: true });
GlobalFonts.registerFromPath(path.join(__dirname, 'assets/ManropeBrand.ttf'), 'LunaVBrand');

const P = { night: '#080f20', paper: '#f2f0e9', gold: '#dac7a0', blue: '#a7bded' };
const FPS = 60, DURATION = 6;
const clamp = v => Math.max(0, Math.min(1, v));
const progress = (t, a, b) => clamp((t - a) / (b - a));
const smooth = x => { x = clamp(x); return x * x * (3 - 2 * x); };
const out = x => 1 - Math.pow(1 - clamp(x), 4);
const inout = x => { x = clamp(x); return x < .5 ? 8*x*x*x*x : 1 - Math.pow(-2*x+2, 4)/2; };
const lerp = (a, b, p) => a + (b-a)*p;
const rgba = (hex, a) => { const n = parseInt(hex.slice(1), 16); return `rgba(${n>>16},${n>>8&255},${n&255},${Math.max(0,a)})`; };
function random(seed) { return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x ^= x + Math.imul(x ^ x >>> 7, 61 | x); return ((x ^ x >>> 14) >>> 0) / 4294967296; }; }
const crescent = new Path2D('M48 38A22 22 0 0 1 26 14a22 22 0 1 0 22 24Z');
const star = new Path2D('m45 10 2 6 6 2-6 2-2 6-2-6-6-2 6-2Z');

// Measure painted paths, excluding the SVG's asymmetric transparent padding.
function inkBounds(paths) {
  const resolution=16, cv=createCanvas(64*resolution,64*resolution);
  const c=cv.getContext('2d');c.scale(resolution,resolution);c.fillStyle='#fff';
  for(const p of paths)c.fill(p);
  const pixels=c.getImageData(0,0,cv.width,cv.height).data;
  let left=cv.width,top=cv.height,right=0,bottom=0;
  for(let y=0;y<cv.height;y++)for(let x=0;x<cv.width;x++) {
    if(pixels[(y*cv.width+x)*4+3]<128)continue;
    left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x+1);bottom=Math.max(bottom,y+1);
  }
  return {left:left/resolution,top:top/resolution,right:right/resolution,bottom:bottom/resolution,
    width:(right-left)/resolution,height:(bottom-top)/resolution,
    centerX:(left+right)/2/resolution,centerY:(top+bottom)/2/resolution};
}
const CRESCENT_INK=inkBounds([crescent]);
const MARK_INK=inkBounds([crescent,star]);

function radial(c, x, y, r, color, strength) {
  const g = c.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, rgba(color, strength));
  g.addColorStop(.35, rgba(color, strength*.38));
  g.addColorStop(1, rgba(color, 0));
  c.fillStyle = g; c.fillRect(x-r, y-r, r*2, r*2);
}
function background(w, h) {
  const bg = createCanvas(w, h), c = bg.getContext('2d');
  c.fillStyle = P.night; c.fillRect(0,0,w,h);
  radial(c, w*.51, h*.47, Math.max(w,h)*.48, '#425d99', .16);
  radial(c, w*.25, h*.25, Math.max(w,h)*.38, '#21385f', .08);
  // Fixed, restrained grain: no flicker between frames.
  const rng = random(817);
  for (let i = 0; i < 14000; i++) { c.fillStyle = `rgba(167,189,237,${rng()*.018})`; c.fillRect(rng()*w,rng()*h,1,1); }
  return bg;
}
function moon(c, x, y, size, t) {
  c.save(); c.translate(x+size/2,y+size/2);
  c.rotate(lerp(-.10,0,out(progress(t,.2,1.2)))); c.scale(size/64,size/64); c.translate(-32,-32);
  const appear = smooth(progress(t,.2,.95));
  radial(c,27,33,55,P.blue,.045*appear);
  const trace = out(progress(t,.18,.78));
  c.save(); c.lineWidth=.65; c.strokeStyle=rgba(P.paper,.65*(1-smooth(progress(t,.68,1.05)))); c.setLineDash([180,180]); c.lineDashOffset = 180*(1-trace); c.stroke(crescent); c.restore();
  c.fillStyle = rgba(P.paper,appear); c.fill(crescent);
  const sa = out(progress(t,.58,1.05));
  c.save(); c.translate(45,18); const ss=sa*(1+.12*Math.sin(progress(t,.58,1.35)*Math.PI)); c.scale(ss,ss); c.translate(-45,-18);
  radial(c,45,18,15,P.gold,.13*sa); c.fillStyle = rgba(P.gold,sa); c.fill(star); c.restore();
  c.restore();
}
function setBrand(c,size) { c.font=`${size}px LunaVBrand`; c.letterSpacing=`${-size*.06}px`; c.textBaseline='alphabetic'; c.textAlign='left'; }
function word(c, text, x, baseline, size, color, alpha=1) { setBrand(c,size); c.fillStyle=rgba(color,alpha); c.fillText(text,x,baseline); }
// Sample the actual suffix glyphs. Every dust particle originates inside
// a letter, and its release time also erodes that same piece of the text.
const suffixCache = new Map();
function suffixDust(size) {
  if (suffixCache.has(size)) return suffixCache.get(size);
  const cv=createCanvas(Math.ceil(size*2.5),Math.ceil(size*1.5));
  const cx=cv.getContext('2d'), baseline=Math.ceil(size*1.12);
  word(cx,'ision',4,baseline,size,P.paper);
  const original=cx.getImageData(0,0,cv.width,cv.height);
  const working=cx.createImageData(cv.width,cv.height);
  const rng=random(17441), particles=[];
  setBrand(cx,size); const width=cx.measureText('ision').width;
  const step=2;
  for(let y=0;y<cv.height;y+=step) for(let x=0;x<cv.width;x+=step) {
    const pixels=[]; let coverage=0;
    for(let dy=0;dy<step;dy++) for(let dx=0;dx<step;dx++) {
      if(x+dx>=cv.width || y+dy>=cv.height) continue;
      const a=((y+dy)*cv.width+x+dx)*4+3;
      if(original.data[a]) {pixels.push(a);coverage+=original.data[a]/255;}
    }
    if(!pixels.length) continue;
    particles.push({x:x+step/2,y:y+step/2,pixels,coverage:coverage/(step*step),
      birth:1.47+(1-clamp((x-4)/width))*.83+rng()*.17+Math.sin(y*.105)*.035,
      life:.65+rng()*.47,vx:55+rng()*74,vy:-22-rng()*67,
      phase:rng()*Math.PI*2,r:.65+rng()*.85,gold:rng()<.065});
  }
  const value={cv,cx,original,working,particles,baseline};
  suffixCache.set(size,value); return value;
}
function dissolveSuffix(c,x,baseline,size,t) {
  if(t<1.45) {word(c,'ision',x,baseline,size,P.paper);return;}
  if(t>3.65) return;
  const data=suffixDust(size);
  data.working.data.set(data.original.data);
  for(const p of data.particles) {
    const age=t-p.birth, erosion=smooth(age/.18);
    if(erosion>0) for(const a of p.pixels) data.working.data[a]=Math.round(data.original.data[a]*(1-erosion));
  }
  data.cx.putImageData(data.working,0,0);
  c.drawImage(data.cv,x-4,baseline-data.baseline);
  for(const p of data.particles) {
    const age=t-p.birth;
    if(age<=0 || age>=p.life) continue;
    const u=age/p.life;
    const alpha=p.coverage*.90*smooth(age/.11)*Math.pow(1-u,1.25);
    const flutter=Math.sin(age*7+p.phase)-Math.sin(p.phase);
    const px=x-4+p.x+p.vx*age+24*age*age+flutter*5*age;
    const py=baseline-data.baseline+p.y+p.vy*age-17*age*age+flutter*3*age;
    c.fillStyle=rgba(p.gold?P.gold:P.paper,alpha);
    c.beginPath();c.arc(px,py,p.r*(1-.42*u),0,Math.PI*2);c.fill();
  }
}
function scene(c, w, h, t, bg, transparent=false) {
  const portrait = h>w;
  if (transparent) c.clearRect(0,0,w,h); else c.drawImage(bg,0,0);
  const endFade=1-smooth(progress(t,5.42,6));
  c.save(); c.globalAlpha=endFade;
  // Composition is authored in a 1920-wide design space, then recomposed for 9:16.
  const scale = portrait ? .91 : w/1920;
  c.translate(w/2,h/2); c.scale(scale,scale); c.translate(-960,-540);
  const settle=inout(progress(t,2.66,3.46));
  const fsiz=portrait ? 164 : 178;
  setBrand(c,fsiz);
  const textMetrics=c.measureText('LunaV');
  const baseW=textMetrics.width;
  const suffixW=c.measureText('ision').width;
  const dotMetrics=c.measureText('.'),dotW=dotMetrics.width;
  const textHeight=textMetrics.actualBoundingBoxAscent+textMetrics.actualBoundingBoxDescent;
  const moonFinal=textHeight*1.05/CRESCENT_INK.height*64;
  const moonScale=moonFinal/64;
  const markWidth=MARK_INK.width*moonScale;
  const textLeft=-textMetrics.actualBoundingBoxLeft;
  const textRight=Math.max(textMetrics.actualBoundingBoxRight,baseW+dotMetrics.actualBoundingBoxRight);
  const gap=fsiz*.24;
  const finalW=markWidth+gap+textRight-textLeft;
  const finalStart=960-finalW/2;
  const initialX=960-(baseW+suffixW)/2;
  const finalX=finalStart+markWidth+gap-textLeft;
  const wordX=lerp(initialX,finalX,settle);
  const finalCenterY=540;
  const finalBaseline=finalCenterY+(textMetrics.actualBoundingBoxAscent-textMetrics.actualBoundingBoxDescent)/2;
  const baseline=lerp(610,finalBaseline,settle);
  const finalMoonX=finalStart-MARK_INK.left*moonScale;
  const finalMoonY=finalCenterY-CRESCENT_INK.centerY*moonScale;
  const initialMoonX=960-CRESCENT_INK.centerX*moonScale;
  const initialMoonY=374-CRESCENT_INK.centerY*moonScale;
  const mx=lerp(initialMoonX,finalMoonX,out(progress(t,2.66,3.13)));
  const my=lerp(initialMoonY,finalMoonY,inout(progress(t,3.00,3.46)));
  moon(c,mx,my,moonFinal,t);

  // Individual letters rise into the initial LunaVision wordmark.
  const full='LunaVision';
  const revealDone=t>=1.35;
  if (!revealDone) {
    for (let i=0;i<full.length;i++) {
      setBrand(c,fsiz);
      const fragment=i<5?full.slice(0,i+1):full.slice(5,i+1);
      const x=initialX+(i<5?0:baseW)+c.measureText(fragment).width-c.measureText(full[i]).width;
      const p=out(progress(t,.50+i*.035,1.00+i*.035));
      word(c,full[i],x,baseline+18*(1-p),fsiz,P.paper,p);
    }
  } else {
    word(c,'LunaV',wordX,baseline,fsiz,P.paper);
    dissolveSuffix(c,initialX+baseW,610,fsiz,t);
  }
  const dotAlpha=out(progress(t,3.06,3.45));
  if(dotAlpha>0) {
    const dx=wordX+baseW, dy=baseline;
    radial(c,dx+dotW*.4,dy-9,42,P.gold,.13*Math.sin(dotAlpha*Math.PI));
    word(c,'.',dx,dy+9*(1-dotAlpha),fsiz,P.gold,dotAlpha);
  }

  c.restore();
}

async function render(format, stills=false) {
  const [w,h]=format==='portrait'?[1080,1920]:[1920,1080];
  const cv=createCanvas(w,h), c=cv.getContext('2d');
  const bg=background(w,h);
  if(stills) {
    for(const t of [.55,1.25,1.70,1.95,2.20,2.45,2.70,3.10,3.20,3.30,3.50,4.55,5.75]) {
      scene(c,w,h,t,bg); const f=path.join(PREVIEW,`${format}-${t.toFixed(2)}.png`); fs.writeFileSync(f,cv.toBuffer('image/png'));
    }
    scene(c,w,h,4.55,bg); fs.writeFileSync(path.join(OUT,`LunaV-${format}-poster.png`),cv.toBuffer('image/png'));
    console.log(`Stills ready: ${format}`); return;
  }
  const ratio=format==='portrait'?'9x16':'16x9';
  const target=path.join(OUT,`LunaV-Intro-${ratio}-Silent.mp4`);
  const ff=spawn('ffmpeg',['-hide_banner','-loglevel','warning','-y','-f','rawvideo','-pixel_format','rgba','-video_size',`${w}x${h}`,'-framerate',String(FPS),'-i','pipe:0','-an','-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709','-c:v','libx264','-preset','slow','-crf','17','-pix_fmt','yuv420p','-profile:v','high','-level:v','4.2','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-movflags','+faststart','-metadata','title=LunaV — A little light','-metadata','artist=Wachirawich Kripindakul',target],{stdio:['pipe','ignore','pipe']});
  let err=''; ff.stderr.on('data',d=>{err+=d.toString();});
  const finished=new Promise((resolve,reject)=>{ff.once('error',reject);ff.once('close',code=>code===0?resolve():reject(new Error(`FFmpeg exit ${code}: ${err}`)));});
  for(let f=0;f<FPS*DURATION;f++) {
    scene(c,w,h,f/FPS,bg);
    const pixels=c.getImageData(0,0,w,h).data;
    if(!ff.stdin.write(Buffer.from(pixels.buffer,pixels.byteOffset,pixels.byteLength))) await once(ff.stdin,'drain');
    if(f%60===0) console.log(`${format}: ${f/FPS}/${DURATION}s`);
  }
  ff.stdin.end(); await finished; console.log(`Rendered ${target}`);
  const wav=path.join(__dirname,'lunav-sonic-logo.wav');
  if(fs.existsSync(wav)) {
    const withAudio=path.join(OUT,`LunaV-Intro-${ratio}.mp4`);
    const mux=spawnSync('ffmpeg',['-hide_banner','-loglevel','error','-y','-i',target,'-i',wav,'-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-b:a','256k','-ar','48000','-t',String(DURATION),'-movflags','+faststart',withAudio],{encoding:'utf8'});
    if(mux.status!==0) throw new Error(mux.stderr||'Audio mux failed');
    console.log(`Sound version: ${withAudio}`);
  }
}

(async()=>{
  const args=process.argv.slice(2);
  const selected=args.includes('--format')?args[args.indexOf('--format')+1]:null;
  for(const f of selected?[selected]:['landscape','portrait']) await render(f,args.includes('--stills'));
})().catch(e=>{console.error(e);process.exit(1);});
