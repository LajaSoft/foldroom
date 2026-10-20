import {add,sub,mul,dot,cross,norm,rotate,HALF,createBall,moveBall,limitBallMotion} from './core.js';

export function setPlayerMode(player,mode) {
  if(mode==='ball') {
    if(player.mode==='ball')return;
    Object.assign(player,{...createBall(0),room:player.room,p:sub(player.p,mul(player.up,.5)),up:[...player.up],velocity:[...player.velocity],forward:[...player.forward],pitch:0,mode:'ball',controlled:true,cameraForward:[...player.forward],cameraUp:[...player.up]});
    player.omega=[0,0,0];
    player.motorAxis=norm(cross(player.up,player.forward));
    return;
  }
  if(player.mode==='ball')player.p=add(player.p,mul(player.up,.5));
  for(const key of ['radius','omega','motorAxis','spin','controlled','cameraForward','cameraUp'])delete player[key];
  player.mode='walk';
}

// Steering always targets the side of the rendered screen, including while
// the inertial camera lags behind a rebound or a gravity transition.
export function steerPlayerBall(player,side,dt) {
  side=Math.max(-1,Math.min(1,side));
  const speed=Math.hypot(...player.velocity);
  if(Math.abs(side)<1e-6)return;
  if(speed<.12){
    const turn=-1.8*side*dt;
    const q=[...mul(player.cameraUp,Math.sin(turn/2)),Math.cos(turn/2)];
    player.cameraForward=norm(rotate(player.cameraForward,q));
    return;
  }
  const screenRight=norm(cross(player.cameraForward,player.cameraUp));
  const target=mul(screenRight,Math.sign(side));
  const direction=norm(player.velocity);
  const angle=Math.acos(Math.max(-1,Math.min(1,dot(direction,target))));
  if(angle<1e-8)return;
  let axis=cross(direction,target);
  if(Math.hypot(...axis)<1e-6)axis=player.cameraUp;
  axis=norm(axis);
  const turn=Math.min(angle,1.8*Math.abs(side)*dt);
  const q=[...mul(axis,Math.sin(turn/2)),Math.cos(turn/2)];
  const retention=Math.exp(-.12*turn);
  player.velocity=mul(rotate(player.velocity,q),retention);
  player.omega=mul(rotate(player.omega,q),retention);
}

export function drivePlayerBall(maze,player,dt,forwardAmount,sideAmount,boost=1) {
  steerPlayerBall(player,sideAmount,dt);
  if(forwardAmount<0){
    const retention=Math.exp(-3*Math.min(1,-forwardAmount)*dt);
    player.velocity=mul(player.velocity,retention);
    player.omega=mul(player.omega,retention);
  }
  if(forwardAmount>0){
    const impulse=mul(player.cameraForward,4*boost*dt*Math.min(1,forwardAmount));
    player.velocity=add(player.velocity,impulse);
    player.omega=add(player.omega,mul(cross(player.up,impulse),1/player.radius));
  }
  moveBall(maze,player,dt);
}

export function smoothDirection(current,target,dt,axisHint) {
  const angle=Math.acos(Math.max(-1,Math.min(1,dot(current,target))));
  if(angle<1e-8)return [...target];
  let axis=cross(current,target);
  if(Math.hypot(...axis)<1e-6)axis=sub(axisHint,mul(current,dot(axisHint,current)));
  axis=norm(axis);
  const turn=Math.min(angle*(1-Math.exp(-4*dt)),2.5*dt);
  const q=[...mul(axis,Math.sin(turn/2)),Math.cos(turn/2)];
  return norm(rotate(current,q));
}

export function updateBallCamera(player,dt) {
  const speed=Math.hypot(...player.velocity);
  const target=speed>.12?norm(player.velocity):player.cameraForward;
  const forward=smoothDirection(player.cameraForward,target,dt,player.cameraUp);
  let up=sub(player.cameraUp,mul(forward,dot(player.cameraUp,forward)));
  if(Math.hypot(...up)<1e-5)up=cross(cross(forward,player.forward),forward);
  up=norm(up);
  const gravityUp=sub(player.up,mul(forward,dot(player.up,forward)));
  if(Math.hypot(...gravityUp)>.15)up=smoothDirection(up,norm(gravityUp),dt,forward);
  player.cameraForward=forward;
  player.cameraUp=norm(sub(up,mul(forward,dot(up,forward))));
}

export function ballCameraFrame(player) {
  // Manual pitch offsets the motion-following frame, including in free fall.
  const pitch=player.pitch??0,cosine=Math.cos(pitch),sine=Math.sin(pitch);
  const forward=norm(add(mul(player.cameraForward,cosine),mul(player.cameraUp,sine)));
  const up=norm(sub(mul(player.cameraUp,cosine),mul(player.cameraForward,sine)));
  return {room:player.room,p:[...player.p],forward,up,gravityUp:player.up};
}

export function resolveSphereContacts(actors,maze) {
  for(let a=0;a<actors.length;a++)for(let b=a+1;b<actors.length;b++) {
    const first=actors[a],second=actors[b];
    if(first.room!==second.room)continue;
    const delta=sub(second.p,first.p),distance=Math.hypot(...delta),radius=first.radius+second.radius;
    if(distance>=radius)continue;
    const normal=distance>1e-8?mul(delta,1/distance):[1,0,0];
    const correction=mul(normal,(radius-distance)/2);
    first.p=sub(first.p,correction);second.p=add(second.p,correction);
    for(const actor of [first,second])for(let axis=0;axis<3;axis++) {
      const sign=actor.p[axis]>=0?1:-1,face=axis*2+(sign<0?1:0);
      if(!maze.rooms[actor.room].links[face])actor.p[axis]=sign*Math.min(Math.abs(actor.p[axis]),HALF-actor.radius);
    }
    const closing=dot(sub(second.velocity,first.velocity),normal);
    if(closing>=0)continue;
    const impulse=mul(normal,-closing*.93);
    first.velocity=sub(first.velocity,impulse);second.velocity=add(second.velocity,impulse);
    limitBallMotion(first);limitBallMotion(second);
  }
}
