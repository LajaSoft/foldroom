import {setPlayerMode,steerPlayerBall,drivePlayerBall,updateBallCamera,ballCameraFrame,resolveSphereContacts} from './player-ball.js';
import {attachTouchControls} from './touch.js';
import {attachPointerControls} from './pointer.js';
import {attachMusicControls} from './music.js';
import {OverviewRenderer, overviewCamera, zoomCameraDistance} from './overview.js';
import {exportState, importState, initialPlayer} from './state.js';
import {
  Maze,MAX_ROOMS,limitBallMotion,movePlayer,createBall,moveBall,cameraFrame,HALF,add,sub,mul,dot,cross,norm,normals,rotate,faceOf,faceUV,intersect
}
from './core.js';
import {
  vertex,fragment
}
from './shaders.js';
const $=id=>document.getElementById(id);
const canvas=$('world');
const gl=canvas.getContext('webgl2', {
  antialias:false,alpha:false,powerPreference:'high-performance'
}
);
if(!gl) {
  $('fatal').hidden=false;
  $('fatal').textContent='This game requires a browser with WebGL 2.';
  throw new Error('WebGL 2 unavailable');
}
function compile(type,source) {
  const shader=gl.createShader(type);
  gl.shaderSource(shader,source);
  gl.compileShader(shader);
  if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(shader));
  return shader;
}
const program=gl.createProgram();
try {
  gl.attachShader(program,compile(gl.VERTEX_SHADER,vertex));
  gl.attachShader(program,compile(gl.FRAGMENT_SHADER,fragment));
  gl.linkProgram(program);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(program));
}
catch(error) {
  $('fatal').hidden=false;
  $('fatal').textContent='Could not start WebGL: '+error.message;
  throw error;
}
gl.useProgram(program);
const worldVAO = gl.createVertexArray();
gl.bindVertexArray(worldVAO);
const quad=gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER,quad);
gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
const location=gl.getAttribLocation(program,'position');
gl.enableVertexAttribArray(location);
gl.vertexAttribPointer(location,2,gl.FLOAT,false,0,0);
const uniforms=Object.fromEntries(['resolution','eye','forward','up','right','roomId','topology','markings','time','balls','ballCount'].map(name=>[name,gl.getUniformLocation(program,name)]));
function texture(unit,width,height,internal,format,type,data) {
  const tex=gl.createTexture();
  gl.activeTexture(gl.TEXTURE0+unit);
  gl.bindTexture(gl.TEXTURE_2D,tex);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  gl.texImage2D(gl.TEXTURE_2D,0,internal,width,height,0,format,type,data);
  return tex;
}
const topologyData=new Float32Array(1024*Math.ceil(12*MAX_ROOMS/1024)*4);
const topologyTexture=texture(0,1024,Math.ceil(12*MAX_ROOMS/1024),gl.RGBA32F,gl.RGBA,gl.FLOAT,topologyData);
const markingTexture=texture(1,2048,1024,gl.RGBA8,gl.RGBA,gl.UNSIGNED_BYTE,null);
gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
gl.uniform1i(uniforms.topology,0);
gl.uniform1i(uniforms.markings,1);
let maze=new Maze();
const balls=[];
const ballData=new Float32Array(3*64*4);
const ballTexture=texture(2,3,64,gl.RGBA32F,gl.RGBA,gl.FLOAT,ballData);
gl.uniform1i(uniforms.balls,2);
function spawnBall() {
  if(balls.length>=16) {
    toast('Up to 16 balls can run at once');
    return;
  }
  const ball=createBall();
  const candidates=[[0,0],[1.2,0],[-1.2,0],[0,1.2],[0,-1.2],[1.2,1.2],[-1.2,-1.2],[1.2,-1.2],[-1.2,1.2]];
  const location=candidates.find(([x,z])=>balls.every(other=>other.room!==0||Math.hypot(other.p[0]-x,other.p[1]+2.49,other.p[2]-z)>1.05));
  if(!location) {
    toast('The spawn area is occupied · wait for the balls to move away');
    return;
  }
  ball.p=[location[0],-2.49,location[1]];
  balls.push(ball);
  $('ballcount').textContent=String(balls.length).padStart(2,'0');
  toast('Ball spawned in the starting room');
}
$('spawn').onclick=spawnBall;
function uploadBalls() {
  const visible=[];
  for(const ball of balls) {
    visible.push(ball);
    for(let face=0;face<6;face++) {
      const link=maze.rooms[ball.room].links[face];
      if(!link||dot(ball.p,normals[face])<HALF-ball.radius)continue;
      const moved=maze.transport(ball.room,face,ball.p,[ball.up]);
      const a=link.q,b=ball.spin;
      const xyz=add(add(mul(b.slice(0,3),a[3]),mul(a.slice(0,3),b[3])),cross(a.slice(0,3),b.slice(0,3)));
      visible.push( {
        ...ball,room:moved.room,p:moved.p,up:moved.vectors[0],spin:[...xyz,a[3]*b[3]-dot(a.slice(0,3),b.slice(0,3))]
      }
      );
    }
  }
  visible.slice(0,64).forEach((ball,i)=>ballData.set([...ball.p,ball.radius,...ball.up,ball.room,...ball.spin],i*12));
  gl.activeTexture(gl.TEXTURE2);
  gl.bindTexture(gl.TEXTURE_2D,ballTexture);
  gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,3,64,gl.RGBA,gl.FLOAT,ballData);
  gl.uniform1i(uniforms.ballCount,Math.min(64,visible.length));
}
const player= {
  room:0,p:[0,-2,1.1],forward:norm([.18,0,-1]),up:[0,1,0],velocity:[0,0,0],pitch:0
}
;
const touchMode=matchMedia('(any-pointer: coarse)').matches;
const touchMove={forward:0,side:0};
const keys=new Set(), markerCanvases=[];
let active=false,started=false,drawing=false,lastMark=null,markerCursor=[0,0],lastTime=0,toastTimer,dirty=true;
const faceNames=['+X / CORAL','−X / MINT','+Y / IVORY','−Y / BLUE','+Z / LILAC','−Z / OCHRE'];
const axisNames=['+X','−X','+Y','−Y','+Z','−Z'];
function toast(message) {
  $('toast').textContent=message;
  $('toast').classList.add('show');
  clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>$('toast').classList.remove('show'),2600);
}
function updateTopology() {
  topologyData.fill(0);
  for(const room of maze.rooms)for(let f=0;f<6;f++) {
    const i=(room.id*12+f*2)*4;
    const link=room.links[f];
    topologyData[i+2]=room.markers[f]+1;
    if(!link)continue;
    topologyData[i]=link.target+1;
    topologyData[i+1]=link.face;
    topologyData[i+3]=link.kind==='straight'?1:2;
    topologyData.set(link.q,i+4);
  }
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D,topologyTexture);
  const rows = Math.ceil(maze.rooms.length * 12 / 1024);
  gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,1024,rows,gl.RGBA,gl.FLOAT,topologyData.subarray(0,rows*1024*4));
  dirty=false;
}
let cameraDistance = 0;
function camera() {
  const frame = player.mode==='ball'?ballCameraFrame(player):cameraFrame(maze, player);
  return overviewCamera(maze, frame, cameraDistance);
}
const overview = new OverviewRenderer(gl, (vertexSource, fragmentSource) => {
  const result = gl.createProgram();
  gl.attachShader(result, compile(gl.VERTEX_SHADER, vertexSource));
  gl.attachShader(result, compile(gl.FRAGMENT_SHADER, fragmentSource));
  gl.linkProgram(result);
  if (!gl.getProgramParameter(result, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(result));
  return result;
});
function zoom(delta){cameraDistance=zoomCameraDistance(cameraDistance,delta);}
canvas.addEventListener('wheel', event => {
  if (!active) return;
  event.preventDefault();
  const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? innerHeight : 1);
  zoom(delta);
}, {passive: false});
function removeOldestBall() {
  if (!balls.length) { toast('No balls yet'); return; }
  balls.shift();
  $('ballcount').textContent = String(balls.length).padStart(2, '0');
  toast('Oldest ball removed');
}
function aim() {
  const view=camera();
  const right=norm(cross(view.forward,view.up));
  const scale=.72;
  const direction=norm(add(view.forward,add(mul(right,markerCursor[0]*2/innerHeight*scale),mul(view.up,-markerCursor[1]*2/innerHeight*scale))));
  return {
    ...intersect(view.p,direction),room:view.room,up:view.gravityUp
  }
  ;
}
function updateHUD() {
  const room=maze.rooms[player.room];
  $('roomid').textContent=String(player.room+1).padStart(3,'0');
  $('coords').textContent=room.cell.join(' : ');
  $('rooms').textContent=String(maze.rooms.length).padStart(2,'0');
  $('passages').textContent=String(maze.passages).padStart(2,'0');
  $('gravity').textContent=axisNames[faceOf(mul(player.up,-1))];
  if(cameraDistance>0){$('targetlabel').textContent='OVERVIEW';$('targetname').textContent=touchMode?'PINCH — ZOOM IN / OUT':'SCROLL — ZOOM IN / OUT';return;}
  const target=aim();
  if(target.face<0)return;
  const link=maze.rooms[target.room].links[target.face];
  $('targetlabel').textContent=drawing?'MARKER':link?'PASSAGE · DEL TO REMOVE':'WALL';
  $('targetname').textContent=link?`${link.kind==='straight'?'STRAIGHT':'FOLD'} / ${String(link.target+1).padStart(3,'0')}`:faceNames[target.face];
}
function setActive(value) {
  active=value;
  if(active){started=true;$('start').hidden=true;$('pause').hidden=true;}
  if(!active&&started)$('pause').hidden=false;
  document.body.classList.toggle('playing',active);
  document.body.classList.toggle('menu',!active);
  keys.clear();touchMove.forward=0;touchMove.side=0;drawing=false;lastMark=null;markerCursor=[0,0];updateCursor();
}
const pointerControls=touchMode?null:attachPointerControls({
  canvas,document,window,isActive:()=>active,setActive,onLook:mouseLook,
  onError:error=>console.warn('Pointer lock unavailable; drag controls enabled.',error),
  onMode:mode=>{
    const drag=mode==='drag';
    document.body.classList.toggle('drag-look',drag);
    $('pointerHint').hidden=!drag;
    if(drag)toast('Drag with middle mouse or Alt + left mouse to look. Esc pauses.');
  }
});
function enter() {
  if(touchMode){setActive(true);return;}
  return pointerControls.enter();
}
function pause() {
  if(touchMode){setActive(false);return;}
  pointerControls.pause();
}
$('play').onclick=enter;
$('resume').onclick=enter;
$('help').onclick=()=> {
  if(active) {
    pause();
    return;
  }
  $('start').hidden=true;
  $('pause').hidden=false;
}
;
document.body.classList.add('menu');
canvas.addEventListener('click',()=> {
  if(!active&&started)enter();
}
);
document.addEventListener('contextmenu',e=>e.preventDefault());
function updateCursor() {
  const crosshair=$('crosshair');
  crosshair.style.left=`calc(50% + ${markerCursor[0]}px)`;
  crosshair.style.top=`calc(50% + ${markerCursor[1]}px)`;
  crosshair.classList.toggle('marker',keys.has('Shift'));
  $('target').style.left=`calc(50% + ${markerCursor[0]}px)`;
  $('target').style.top=`calc(50% + ${markerCursor[1]+30}px)`;
}
document.addEventListener('keydown',e=> {
  if($('jsonDialog').open)return;
  if(e.target?.closest?.('button,input,textarea') && e.target.id!=='play' && e.target.id!=='resume')return;
  if(e.code==='Enter'&&!active) {
    enter();return;
  }
  if(e.code==='Escape'&&active){pause();return;}
  if(!active)return;if(['KeyW','KeyA','KeyS','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Delete','Space','ShiftLeft','ShiftRight'].includes(e.code))e.preventDefault();keys.add(e.key==='Shift'?'Shift':e.code);if(e.key==='Shift')updateCursor();if(e.code==='KeyB'&&!e.repeat){if(e.shiftKey)removeOldestBall();else spawnBall();}if(e.code==='Delete'&&!e.repeat) {
    if(cameraDistance>0){toast('Scroll back to first-person view to edit');return;}
    const hit=aim();if(maze.remove(hit.room,hit.face)) {
      dirty=true;toast('Passage closed on both sides');return;
    }
    toast('Aim at a passage');
  }
}
);
document.addEventListener('keyup',e=> {
  keys.delete(e.key==='Shift'?'Shift':e.code);if(e.key==='Shift') {
    markerCursor=[0,0];drawing=false;lastMark=null;updateCursor();
  }
}
);
window.addEventListener('blur',()=> {
  keys.clear();touchMove.forward=0;touchMove.side=0;drawing=false;lastMark=null;
  if(touchMode&&active)setActive(false);
}
);
function mouseLook(dx,dy) {
  if(!active||touchMode)return;
  if(keys.has('Shift') && drawing) {
    markerCursor[0]=Math.max(-innerWidth*.46,Math.min(innerWidth*.46,markerCursor[0]+dx));markerCursor[1]=Math.max(-innerHeight*.43,Math.min(innerHeight*.43,markerCursor[1]+dy));updateCursor();mark();return;
  }
  look(dx,dy);
}
function look(dx,dy) {
  if(player.mode==='ball'){
    steerPlayerBall(player,Math.sign(dx),Math.min(.15,Math.abs(dx)*.0024/1.8));
    const pitchLimit=89*Math.PI/180;
    player.pitch=Math.max(-pitchLimit,Math.min(pitchLimit,player.pitch-dy*.0024));
    return;
  }
  const angle = -dx * .0024;
  const q = [...mul(player.up, Math.sin(angle / 2)), Math.cos(angle / 2)];
  player.forward = norm(rotate(player.forward, q));
  const pitchLimit = 89 * Math.PI / 180;
  player.pitch = Math.max(-pitchLimit, Math.min(pitchLimit, player.pitch - dy * .0024));
}
document.addEventListener('mousedown',e=> {
  if(!active||touchMode||e.target!==canvas||pointerControls.isLookGesture(e))return;e.preventDefault();if(cameraDistance>0){toast('Scroll back to first-person view to edit');return;}if(e.button===0&&e.shiftKey) {
    drawing=true;lastMark=null;mark();return;
  }
  if(e.button!==0&&e.button!==2)return;
  carve(e.button===0?'straight':e.shiftKey?'down':'up');
});
function carve(kind) {
  if(!active)return;
  if(cameraDistance>0){toast('Return to first-person view to edit');return;}
  const hit=aim();
  try {
    const link=maze.create(hit.room,hit.face,kind,hit.up);dirty=true;toast(`${kind==='straight'?'Straight passage':kind==='up'?'Upward passage':'Downward passage'} · room ${String(link.target+1).padStart(3,'0')}`);
  } catch(error) {toast(error.message);}
}
canvas.addEventListener('mousemove',e=> {
  if(active&&drawing&&document.pointerLockElement!==canvas)mouseLook(e.movementX,e.movementY);
});
document.addEventListener('mouseup',()=> {
  drawing=false;lastMark=null;markerCursor=[0,0];updateCursor();
}
);
function mark() {
  const hit=aim();
  if(hit.face<0)return;
  const room=maze.rooms[hit.room];
  if(room.links[hit.face]) {
    lastMark=null;
    return;
  }
  let slot=room.markers[hit.face];
  if(slot<0) {
    if(markerCanvases.length>=128) {
      toast('Marker limit reached: 128 marked faces');
      drawing=false;
      return;
    }
    slot=markerCanvases.length;
    room.markers[hit.face]=slot;
    const surface=document.createElement('canvas');
    surface.width=surface.height=128;
    markerCanvases.push(surface);
    dirty=true;
  }
  const surface=markerCanvases[slot],ctx=surface.getContext('2d');
  const uv=faceUV(hit.point,hit.face).map(v=>v*127);
  const from=lastMark?.slot===slot?lastMark.uv:uv;
  ctx.lineCap='round';
  ctx.lineJoin='round';
  ctx.strokeStyle='#20251b';
  ctx.lineWidth=3.8;
  ctx.beginPath();
  ctx.moveTo(...from);
  ctx.lineTo(uv[0]+.01,uv[1]+.01);
  ctx.stroke();
  ctx.strokeStyle='#f4f09c';
  ctx.lineWidth=2;
  ctx.beginPath();
  ctx.moveTo(...from);
  ctx.lineTo(uv[0]+.01,uv[1]+.01);
  ctx.stroke();
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D,markingTexture);
  gl.texSubImage2D(gl.TEXTURE_2D,0,(slot%16)*128,Math.floor(slot/16)*128,gl.RGBA,gl.UNSIGNED_BYTE,surface);
  lastMark= {
    slot,uv
  }
  ;
}
function step(dt) {
  const forwardAmount=Number(keys.has('KeyW')||keys.has('ArrowUp'))-Number(keys.has('KeyS')||keys.has('ArrowDown'))+touchMove.forward;
  const sideAmount=Number(keys.has('KeyD')||keys.has('ArrowRight'))-Number(keys.has('KeyA')||keys.has('ArrowLeft'))+touchMove.side;
  const actors=player.mode==='ball'?[...balls,player]:balls;
  const fastest=Math.max(0,...actors.map(actor=>Math.hypot(...actor.velocity)));
  const count=Math.max(1,Math.ceil((fastest+20*dt)*dt/.2));
  const part=dt/count;
  for(let i=0;i<count;i++){
    if(player.mode==='ball')drivePlayerBall(maze,player,part,forwardAmount,sideAmount,keys.has('Shift')?5:1);
    if(player.mode!=='ball')movePlayer(maze,player,part,forwardAmount,sideAmount,keys.has('Shift')?5:1);
    for(const ball of balls)moveBall(maze,ball,part);
    resolveSphereContacts(actors,maze);
    if(player.mode==='ball')updateBallCamera(player,part);
  }
}
function resize() {
  const ratio=Math.min(devicePixelRatio,touchMode?1:1.5),cap=Math.min(1,1500/(innerWidth*ratio));
  canvas.width=Math.round(innerWidth*ratio*cap);
  canvas.height=Math.round(innerHeight*ratio*cap);
  gl.viewport(0,0,canvas.width,canvas.height);
}
window.addEventListener('resize',resize);
resize();
function frame(now) {
  const dt=Math.min((now-lastTime)/1000,.05);
  lastTime=now;
  if(active) {
    const count=Math.ceil(dt/.012);
    for(let i=0;i<count;i++)step(dt/count);
  }
  gl.useProgram(program);
  gl.bindVertexArray(worldVAO);
  if(dirty)updateTopology();
  uploadBalls();
  const view=camera();
  const right=norm(cross(view.forward,view.up));
  gl.uniform2f(uniforms.resolution,canvas.width,canvas.height);
  gl.uniform3fv(uniforms.eye,view.p);
  gl.uniform3fv(uniforms.forward,view.forward);
  gl.uniform3fv(uniforms.up,view.up);
  gl.uniform3fv(uniforms.right,right);
  gl.uniform1i(uniforms.roomId,view.room);
  gl.uniform1f(uniforms.time,now*.001);
  if(view.outside)overview.render(maze,player,balls,view,right,cameraDistance);
  else {gl.disable(gl.DEPTH_TEST);gl.disable(gl.BLEND);gl.drawArrays(gl.TRIANGLES,0,3);}
  updateHUD();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
canvas.addEventListener('webglcontextlost',e=> {
  e.preventDefault();pause();$('fatal').hidden=false;$('fatal').textContent='WebGL context lost. Reload the page to restart.';
}
);

// Import builds and validates a replacement before changing the running game.
const jsonDialog = $('jsonDialog');
function openJsonDialog(mode, value = '') {
  $('jsonTitle').textContent = mode === 'import' ? 'Import JSON' : 'Export JSON';
  $('jsonText').value = value;
  $('jsonText').readOnly = mode !== 'import';
  $('jsonApply').hidden = mode !== 'import';
  $('jsonError').textContent = '';
  $('jsonHint').textContent = mode === 'import'
    ? 'Paste an exported JSON. The current labyrinth will be replaced after validation.'
    : 'Clipboard access is unavailable. Copy the selected JSON manually.';
  jsonDialog.showModal();
  $('jsonText').focus();
  if (mode === 'export') $('jsonText').select();
}
function updateModeButton(){
  const ballMode=player.mode==='ball';
  $('playerMode').textContent=ballMode?'Mode: Ball':'Mode: Walk';
  $('playerMode').setAttribute('aria-pressed',String(ballMode));
  document.querySelector('.instructions>div:first-child span').textContent=ballMode?'Steer left / right; look up / down':'Look in any direction';
  document.querySelector('.touch-help').textContent=ballMode?'Joystick up accelerates, down brakes, left / right turns. Drag horizontally to steer, vertically to look up / down; pinch to zoom. The camera follows motion.':'Move with the left joystick. Drag on the screen to look around. Pinch with two fingers to zoom. The right buttons carve the wall under the crosshair.';
  $('modeHint').textContent=ballMode?'W / joystick up accelerates; S / down brakes. A / D turns toward screen left / right, losing a little speed. Mouse / drag steers horizontally and adds a vertical look offset.':'Switch to Ball mode to roll, coast and push other balls.';
}
$('playerMode').onclick=()=>{
  setPlayerMode(player,player.mode==='ball'?'walk':'ball');
  cameraDistance=0;keys.clear();touchMove.forward=0;touchMove.side=0;
  updateModeButton();updateHUD();
};
updateModeButton();
$('pauseSpawn').onclick = spawnBall;
$('jumpStart').onclick = () => {
  const mode=player.mode;
  setPlayerMode(player,'walk');
  Object.assign(player, initialPlayer());
  if(mode==='ball')setPlayerMode(player,'ball');
  cameraDistance = 0;
  keys.clear();
  drawing = false;
  lastMark = null;
  markerCursor = [0, 0];
  updateCursor();
  updateHUD();
  toast('You are in the starting room');
};
$('exportState').onclick = async () => {
  const text = exportState(maze, player, balls, markerCanvases.map(surface => surface.toDataURL('image/png')));
  try {
    await navigator.clipboard.writeText(text);
    toast('JSON copied to the clipboard');
  } catch {
    openJsonDialog('export', text);
  }
};
$('importState').onclick = () => openJsonDialog('import');
$('jsonCancel').onclick = () => jsonDialog.close();
function decodeMark(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      if (image.width !== 128 || image.height !== 128) {
        reject(new Error('Mark images must be 128 × 128'));
        return;
      }
      const surface = document.createElement('canvas');
      surface.width = surface.height = 128;
      surface.getContext('2d').drawImage(image, 0, 0);
      resolve(surface);
    };
    image.onerror = () => reject(new Error('Corrupt mark image in JSON'));
    image.src = url;
  });
}
function applyRestoredState(restored,surfaces=[]) {
    maze = restored.maze;
    setPlayerMode(player,'walk');
    Object.assign(player, restored.player);
    updateModeButton();
    cameraDistance = 0;
    balls.splice(0, balls.length, ...restored.balls);
    markerCanvases.splice(0, markerCanvases.length, ...surfaces);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, markingTexture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 2048, 1024, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    surfaces.forEach((surface, slot) => gl.texSubImage2D(gl.TEXTURE_2D, 0, (slot % 16) * 128, Math.floor(slot / 16) * 128, gl.RGBA, gl.UNSIGNED_BYTE, surface));
    dirty = true;
    keys.clear();
    drawing = false;
    lastMark = null;
    markerCursor = [0, 0];
    $('ballcount').textContent = String(balls.length).padStart(2, '0');
    updateCursor();
    updateHUD();
    touchMove.forward=0;touchMove.side=0;
}
$('loadExample').onclick=async()=>{
  $('loadExample').disabled=true;
  $('resetMaze').disabled=true;
  try {
    const response=await fetch(new URL('example.json',import.meta.url));
    if(!response.ok)throw new Error('Could not load the example. Please try again.');
    const restored=importState(await response.text());
    const surfaces=await Promise.all(restored.marks.map(decodeMark));
    applyRestoredState(restored,surfaces);
    toast('Example loaded');
  } catch(error) {toast(error.message);}
  finally {$('loadExample').disabled=false;$('resetMaze').disabled=false;}
};
$('resetMaze').onclick=()=>{
  applyRestoredState({maze:new Maze(),player:initialPlayer(),balls:[]});
  toast('Labyrinth reset');
};
$('jsonApply').onclick = async () => {
  $('jsonApply').disabled = true;
  $('jsonCancel').disabled = true;
  try {
    const restored = importState($('jsonText').value);
    const surfaces = await Promise.all(restored.marks.map(decodeMark));
    // The dialog may have been dismissed with Escape during image decoding.
    if (!jsonDialog.open) return;
    applyRestoredState(restored,surfaces);
    jsonDialog.close();
    toast('Labyrinth restored');
  } catch (error) {
    $('jsonError').textContent = error.message;
  } finally {
    $('jsonApply').disabled = false;
    $('jsonCancel').disabled = false;
  }
};

attachMusicControls(toast);

if(touchMode){
  document.body.classList.add('touch');
  attachTouchControls({canvas,isActive:()=>active,onMove:(forward,side)=>{touchMove.forward=forward;touchMove.side=side;},onLook:look,onCarve:carve,onZoom:zoom});
  document.querySelector('.startmeta').textContent='Joystick — move · Drag — look · Pinch — zoom';
  document.querySelector('.touch-note').textContent='Aim at a wall and tap a passage button on the right.';
}
