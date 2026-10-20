export const SIZE = 6;
export const HALF = SIZE / 2;
export const MAX_ROOMS = 10000;
export const BALL_BRAKE_SPEED = 800;
export const BALL_MAX_SPEED = 1200;
export const BALL_MAX_SPIN = 48;
export const add = (a, b) => a.map((v, i) => v + b[i]);
export const sub = (a, b) => a.map((v, i) => v - b[i]);
export const mul = (a, k) => a.map(v => v * k);
export const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
export const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
export const norm = a => mul(a, 1 / (Math.hypot(...a) || 1));
export const normals = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
export const faceOf = v => normals.reduce((best, n, i) => dot(n,v)>dot(normals[best],v) ? i : best, 0);
export const rotate = (v, q) => add(v, mul(cross(q.slice(0,3), add(cross(q.slice(0,3),v), mul(v,q[3]))), 2));
export const inverse = q => [-q[0],-q[1],-q[2],q[3]];
export function rotationBetween(a,b) {
  if (dot(a,b)>0.999) return [0,0,0,1];
  return [...mul(cross(a,b), Math.SQRT1_2), Math.SQRT1_2];
}
export function faceUV(p, face) {
  const axis = Math.floor(face/2);
  return axis===0 ? [p[2]/SIZE+.5,p[1]/SIZE+.5] : axis===1 ? [p[0]/SIZE+.5,p[2]/SIZE+.5] : [p[0]/SIZE+.5,p[1]/SIZE+.5];
}
export function intersect(p,d) {
  let distance=Infinity, face=-1;
  for (let axis=0;axis<3;axis++) {
    if (Math.abs(d[axis])<1e-8) continue;
    const sign=d[axis]>0?1:-1;
    const t=(sign*HALF-p[axis])/d[axis];
    if(t>=-1e-6 && t<distance) {
      distance=Math.max(0,t);
      face=axis*2+(sign<0?1:0);
    }
  }
  return {
    distance,face,point:add(p,mul(d,distance))
  }
  ;
}
export class Maze {
  constructor() {
    this.rooms=[];
    this.cells=new Map();
    this.walls=new Map();
    this.nextLink=1;
    this.room([0,0,0]);
  }
  room(cell) {
    const key=cell.join(',');
    if(this.cells.has(key)) return this.rooms[this.cells.get(key)];
    if(this.rooms.length>=MAX_ROOMS) throw new Error('Room limit reached: 10,000');
    const room= {
      id:this.rooms.length, cell:[...cell], links:Array(6).fill(null), markers:Array(6).fill(-1)
    }
    ;
    this.rooms.push(room);
    this.cells.set(key,room.id);
    return room;
  }
  wallKey(room,face) {
    const a=this.rooms[room].cell, b=add(a,normals[face]);
    return [a.join(','),b.join(',')].sort().join('|');
  }
  thinWalls() {
    const result=new Set();
    for(const room of this.rooms)for(let face=0;face<6;face++) {
      const link=room.links[face];
      if(!link || link.kind==='straight')continue;
      const direction=sub(this.rooms[link.target].cell,room.cell);
      if(dot(direction,normals[face])!==0)continue;
      const opposite=this.cells.get(add(room.cell,normals[face]).join(','));
      if(opposite!==undefined&&!this.rooms[opposite].links[face^1])result.add(this.wallKey(room.id,face));
    }
    return result;
  }
  create(roomId,face,kind,up) {
    const room=this.rooms[roomId];
    if(room.links[face]) throw new Error('A passage already exists here · press Delete to remove it');
    const n=normals[face];
    if(Math.abs(dot(n,up))>.01) throw new Error('Choose a side wall');
    const wallKey=this.wallKey(roomId,face);
    if(kind==='straight' && this.walls.has(wallKey)) throw new Error('This side only allows an upward or downward passage');
    const direction=kind==='straight'?n:mul(up,kind==='up'?1:-1);
    const cell=add(room.cell,direction);
    const targetFace=faceOf(mul(direction,-1));
    const existing=this.cells.get(cell.join(','));
    if(existing!==undefined && this.rooms[existing].links[targetFace]) throw new Error('Another passage occupies the exit');
    const targetKey=[cell.join(','),add(cell,normals[targetFace]).join(',')].sort().join('|');
    if(kind==='straight' && this.walls.has(targetKey)) throw new Error('This wall already contains a folded passage');
    const previousThinWalls=this.thinWalls(), previousCount=this.rooms.length;
    const target=this.room(cell);
    const q=rotationBetween(n,direction), id=this.nextLink++;
    const keys=[...new Set([wallKey,targetKey])];
    room.links[face]= {
      id,target:target.id,face:targetFace,q,kind,keys
    }
    ;
    target.links[targetFace]= {
      id,target:roomId,face,q:inverse(q),kind,keys
    }
    ;
    if([...this.thinWalls()].some(key=>!previousThinWalls.has(key))) {
      room.links[face]=null;
      target.links[targetFace]=null;
      if(this.rooms.length>previousCount){this.rooms.pop();this.cells.delete(cell.join(','));}
      this.nextLink--;
      throw new Error('A folded corner must be open on both sides of the wall');
    }
    for(const key of keys) this.walls.set(key,(this.walls.get(key)||0)+1);
    return room.links[face];
  }
  remove(roomId,face) {
    const link=this.rooms[roomId].links[face];
    if(!link) return false;
    const previousThinWalls=this.thinWalls();
    const reverse=this.rooms[link.target].links[link.face];
    this.rooms[link.target].links[link.face]=null;
    this.rooms[roomId].links[face]=null;
    if([...this.thinWalls()].some(key=>!previousThinWalls.has(key))) {
      this.rooms[roomId].links[face]=link;
      this.rooms[link.target].links[link.face]=reverse;
      throw new Error('Closing this passage would leave a folded corner open on one side');
    }
    for(const key of link.keys) {
      const count=this.walls.get(key)-1;
      if(count) this.walls.set(key,count);
      else this.walls.delete(key);
    }
    return true;
  }
  prune(anchor,actors=[]) {
    const reachable=new Set([anchor]), queue=[anchor];
    for(let i=0;i<queue.length;i++)for(const link of this.rooms[queue[i]].links) {
      if(!link||reachable.has(link.target))continue;
      reachable.add(link.target);queue.push(link.target);
    }
    const retained=this.rooms.filter(room=>reachable.has(room.id));
    const ids=new Map(retained.map((room,id)=>[room.id,id]));
    const offset=retained[0].cell.slice();
    const removed=this.rooms.length-retained.length;
    this.rooms=retained;this.cells.clear();this.walls.clear();
    for(const room of retained) {
      room.id=ids.get(room.id);room.cell=sub(room.cell,offset);
      this.cells.set(room.cell.join(','),room.id);
    }
    const seen=new Set();
    for(const room of retained)for(let face=0;face<6;face++) {
      const link=room.links[face];if(!link)continue;
      link.target=ids.get(link.target);
    }
    for(const room of retained)for(let face=0;face<6;face++) {
      const link=room.links[face];if(!link)continue;
      link.keys=[...new Set([this.wallKey(room.id,face),this.wallKey(link.target,link.face)])];
      if(seen.has(link.id))continue;seen.add(link.id);
      for(const key of link.keys)this.walls.set(key,(this.walls.get(key)||0)+1);
    }
    const surviving=actors.filter(actor=>ids.has(actor.room));
    for(const actor of surviving)actor.room=ids.get(actor.room);
    return {removed,actors:surviving};
  }
  transport(room,face,p,vectors=[]) {
    const link=this.rooms[room].links[face];
    const local=sub(p,mul(normals[face],HALF));
    return {
      room:link.target,p:add(rotate(local,link.q),mul(normals[link.face],HALF)),vectors:vectors.map(v=>rotate(v,link.q))
    }
    ;
  }
  get passages() {
    return this.rooms.reduce((n,r)=>n+r.links.filter(Boolean).length,0)/2;
  }
}
function fitsPortal(player,point,face) {
  for(let axis=0;axis<3;axis++) {
    if(axis===Math.floor(face/2))continue;
    const extent=Math.abs(player.up[axis])>.5?1:.32;
    if(Math.abs(point[axis])>HALF-extent+.02)return false;
  }
  return true;
}
// Distance-bounded integration checks every boundary even at terminal speed.
function motionSteps(dt,velocity,extraSpeed=0) {
  return Math.max(1,Math.ceil((Math.min(BALL_MAX_SPEED,Math.hypot(...velocity))+extraSpeed+8*dt)*dt/.2));
}
export function movePlayer(maze,player,dt,forwardAmount,sideAmount,speedMultiplier=1) {
  dt=Math.max(0,Math.min(dt,.05));
  player.velocity=brakeVector(player.velocity,0);
  if(!player.p.every(v=>Number.isFinite(v)&&Math.abs(v)<=HALF+.6)){
    player.p=mul(player.up,-2);player.velocity=[0,0,0];
  }
  const steps=motionSteps(dt,player.velocity,2.6*speedMultiplier);
  for(let i=0;i<steps;i++)stepPlayer(maze,player,dt/steps,forwardAmount,sideAmount,speedMultiplier);
}
function stepPlayer(maze,player,dt,forwardAmount,sideAmount,speedMultiplier) {
  const right=norm(cross(player.forward,player.up));
  const wish=add(mul(player.forward,forwardAmount),mul(right,sideAmount));
  const walking=mul(norm(wish),2.6*speedMultiplier);
  const falling=dot(player.velocity,player.up)-8*dt;
  player.velocity=brakeVector(add(walking,mul(player.up,falling)),dt);
  let next=add(player.p,mul(player.velocity,dt));
  for(let axis=0;axis<3;axis++) {
    if(Math.abs(next[axis])<1e-8)continue;
    const sign=next[axis]>0?1:-1,face=axis*2+(sign<0?1:0),link=maze.rooms[player.room].links[face];
    const extent=Math.abs(player.up[axis])>.5?1:.32;
    if(link&&fitsPortal(player,next,face)) {
      if(Math.abs(next[axis])>=HALF) {
        const result=maze.transport(player.room,face,next,[player.forward,player.up,player.velocity]);
        player.room=result.room;
        player.p=result.p;
        [player.forward,player.up,player.velocity]=result.vectors;
        player.up=normals[faceOf(player.up)].slice();
        player.forward=norm(sub(player.forward,mul(player.up,dot(player.forward,player.up))));
        return;
      }
      continue;
    }
    if(Math.abs(next[axis])>HALF-extent) {
      next[axis]=sign*(HALF-extent);
      player.velocity[axis]=0;
    }
  }
  player.p=next;
}
export function multiplyQuaternion(a,b) {
  const xyz=add(add(mul(b.slice(0,3),a[3]),mul(a.slice(0,3),b[3])),cross(a.slice(0,3),b.slice(0,3)));
  return [...xyz,a[3]*b[3]-dot(a.slice(0,3),b.slice(0,3))];
}
export function createBall(angle=Math.random()*Math.PI*2) {
  const heading=[Math.cos(angle),0,Math.sin(angle)];
  return {
    room:0,p:[0,-2.49,0],radius:.5,up:[0,1,0],velocity:mul(heading,.8),omega:mul(cross([0,1,0],heading),2.4),motorAxis:cross([0,1,0],heading),spin:[0,0,0,1]
  }
  ;
}
// Retrograde drag increases continuously above the soft threshold; the hard cap
// only catches legacy states, collision spikes and unusually long timesteps.
export function brakeVector(value, dt, soft = BALL_BRAKE_SPEED, hard = BALL_MAX_SPEED) {
  if(!Array.isArray(value)||value.length!==3||!value.every(Number.isFinite))return [0,0,0];
  const speed=Math.hypot(...value);
  if(!Number.isFinite(speed))return [0,0,0];
  if(speed<=soft)return value;
  const limited=Math.min(speed,hard);
  const target=soft+(limited-soft)*Math.exp(-6*Math.max(0,dt));
  return mul(value,target/speed);
}
export function limitBallMotion(ball,dt=0) {
  ball.velocity=brakeVector(ball.velocity,dt);
  ball.omega=brakeVector(ball.omega,dt,24,BALL_MAX_SPIN);
}
export function moveBall(maze,ball,dt) {
  dt=Math.max(0,Math.min(dt,.05));
  limitBallMotion(ball);
  const steps=motionSteps(dt,ball.velocity);
  for(let i=0;i<steps;i++)stepBall(maze,ball,dt/steps);
}
function stepBall(maze,ball,dt) {
  dt=Math.max(0,Math.min(dt,.05));
  limitBallMotion(ball);
  const radius=ball.radius,inertia=.4*radius*radius;
  if(!ball.p.every(v=>Number.isFinite(v)&&Math.abs(v)<=HALF+.6)){
    ball.p=mul(ball.up,-(HALF-radius-.01));ball.velocity=[0,0,0];
  }
  const rollingOmega=sub(ball.omega,mul(ball.up,dot(ball.omega,ball.up)));
  const spinSpeed=Math.hypot(...rollingOmega);
  const motorAxis=spinSpeed>.05?norm(rollingOmega):ball.motorAxis;
  ball.motorAxis=motorAxis;
  // Drive rolling spin, not an unproductive pirouette about local gravity.
  ball.omega=sub(ball.omega,mul(ball.up,dot(ball.omega,ball.up)*Math.min(1,dt*.4)));
  const torque=ball.controlled?0:Math.min(.22,Math.max(0,(2.4-spinSpeed)*.35));
  ball.omega=add(ball.omega,mul(motorAxis,torque/inertia*dt));
  ball.velocity=add(ball.velocity,mul(ball.up,-8*dt));
  limitBallMotion(ball,dt);
  let next=add(ball.p,mul(ball.velocity,dt));
  for(let axis=0;axis<3;axis++) {
    const sign=next[axis]>=0?1:-1,face=axis*2+(sign<0?1:0);
    const link=maze.rooms[ball.room].links[face];
    const fits=next.every((value,i)=>i===axis||Math.abs(value)<=HALF-radius+.002);
    if(link&&fits) {
      if(Math.abs(next[axis])>=HALF) {
        const frame=ball.controlled?[ball.forward,ball.cameraForward,ball.cameraUp]:[];
        const moved=maze.transport(ball.room,face,next,[ball.velocity,ball.up,ball.omega,ball.motorAxis,...frame]);
        ball.room=moved.room;
        ball.p=moved.p;
        [ball.velocity,ball.up,ball.omega,ball.motorAxis]=moved.vectors;
        if(ball.controlled)[ball.forward,ball.cameraForward,ball.cameraUp]=moved.vectors.slice(4);
        ball.up=normals[faceOf(ball.up)].slice();
        ball.spin=multiplyQuaternion(link.q,ball.spin);
        return;
      }
      continue;
    }
    if(Math.abs(next[axis])<=HALF-radius) continue;
    next[axis]=sign*(HALF-radius);
    const normal=mul(normals[face],-1),normalSpeed=dot(ball.velocity,normal);
    const isFloor=dot(normal,ball.up)>.9;
    const restitution=isFloor?.12:.86;
    const normalImpulse=Math.max(0,-normalSpeed*(1+restitution));
    ball.velocity=add(ball.velocity,mul(normal,normalImpulse));
    const contactArm=mul(normal,-radius);
    const contactVelocity=add(ball.velocity,cross(ball.omega,contactArm));
    const slip=sub(contactVelocity,mul(normal,dot(contactVelocity,normal)));
    const slipSpeed=Math.hypot(...slip);
    if(slipSpeed>1e-8) {
      const friction=isFloor?.6:.16;
      const impulse=mul(slip,-Math.min(slipSpeed/(1+radius*radius/inertia),friction*normalImpulse)/slipSpeed);
      ball.velocity=add(ball.velocity,impulse);
      ball.omega=add(ball.omega,mul(cross(contactArm,impulse),1/inertia));
    }
    if(isFloor&&Math.abs(dot(ball.velocity,normal))<.05) ball.velocity=sub(ball.velocity,mul(normal,dot(ball.velocity,normal)));
  }
  ball.p=next;
  limitBallMotion(ball);
  const speed=Math.hypot(...ball.omega);
  if(speed>1e-8) ball.spin=multiplyQuaternion([...mul(ball.omega,Math.sin(speed*dt/2)/speed),Math.cos(speed*dt/2)],ball.spin);
  const length=Math.hypot(...ball.spin);
  ball.spin=ball.spin.map(v=>v/length);
}
// The eye can still be in the previous room while the body is falling through.
export function cameraFrame(maze,player) {
  let room=player.room,p=add(player.p,mul(player.up,.65)),forward=player.forward,up=player.up;
  for(let i=0;i<3;i++) {
    const axis=p.findIndex(v=>Math.abs(v)>HALF+1e-7);
    if(axis<0) break;
    const face=axis*2+(p[axis]<0?1:0);
    if(!maze.rooms[room].links[face]) {
      p[axis]=Math.sign(p[axis])*(HALF-.001);
      continue;
    }
    const transformed=maze.transport(room,face,p,[forward,up]);
    room=transformed.room;
    p=transformed.p;
    [forward,up]=transformed.vectors;
  }
  // Pitch affects the eye frame only; gravity and walking keep their own basis.
  const pitch = player.pitch ?? 0;
  const cosine = Math.cos(pitch);
  const sine = Math.sin(pitch);
  return {
    room,
    p,
    forward: add(mul(forward, cosine), mul(up, sine)),
    up: sub(mul(up, cosine), mul(forward, sine)),
    gravityUp: up,
  };
}
