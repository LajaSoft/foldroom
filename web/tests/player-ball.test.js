import test from 'node:test';
import assert from 'node:assert/strict';
import {Maze,createBall,dot,sub,norm,mul,cross,normals} from '../dist/core.js';
import {initialPlayer,exportState,importState} from '../dist/state.js';
import {setPlayerMode,drivePlayerBall,updateBallCamera,ballCameraFrame,smoothDirection,steerPlayerBall,resolveSphereContacts} from '../dist/player-ball.js';

function actor(){const player=initialPlayer();setPlayerMode(player,'ball');return player;}

test('ball mode has sphere height, input adds rolling momentum and no input does not drive it',()=>{
  const maze=new Maze(),player=actor();
  assert.equal(player.radius,.5);assert.equal(player.p[1],-2.5);
  assert.deepEqual(ballCameraFrame(player).p,player.p);
  for(let i=0;i<100;i++)drivePlayerBall(maze,player,.01,0,0);
  assert.ok(Math.hypot(...player.velocity)<.01);
  for(let i=0;i<25;i++)drivePlayerBall(maze,player,.01,1,0);
  const speed=Math.hypot(...player.velocity);
  assert.ok(speed>.7);
  for(let i=0;i<25;i++)drivePlayerBall(maze,player,.01,0,0);
  assert.ok(Math.hypot(...player.velocity)>.7,'must coast instead of stopping on release');
  setPlayerMode(player,'walk');assert.equal(player.radius,undefined);assert.equal(player.mode,'walk');
});

test('player sphere transfers an impact to a free ball',()=>{
  const maze=new Maze(),player=actor(),ball=createBall(0);
  player.p=[-.45,-2.5,0];player.velocity=[2,0,0];ball.p=[.45,-2.5,0];ball.velocity=[0,0,0];
  resolveSphereContacts([player,ball],maze);
  assert.ok(ball.velocity[0]>1.8);assert.ok(player.velocity[0]<.2);
  assert.ok(Math.hypot(...sub(ball.p,player.p))>=1-1e-8);
});

test('camera reverses gradually without zero vectors, tracks vertical falls and stays stable at rest',()=>{
  const player=actor();player.velocity=mul(player.cameraForward,-2);
  const start=[...player.cameraForward];
  updateBallCamera(player,.01);
  assert.ok(dot(start,player.cameraForward)>.999);
  for(let i=0;i<300;i++)updateBallCamera(player,.01);
  assert.ok(dot(norm(player.velocity),player.cameraForward)>.99);
  player.velocity=[0,-10,0];
  for(let i=0;i<300;i++)updateBallCamera(player,.01);
  assert.ok(dot(norm(player.velocity),player.cameraForward)>.99);
  assert.ok(Math.abs(dot(player.cameraForward,player.cameraUp))<1e-8);
  player.velocity=[0,0,0];const heading=[...player.cameraForward];updateBallCamera(player,.01);
  assert.ok(dot(heading,player.cameraForward)>.999999);
});

test('controlled sphere and its camera frame rotate through a fold and roundtrip in JSON',()=>{
  const maze=new Maze();maze.create(0,5,'up',[0,1,0]);
  const player=actor();player.p=[0,0,-2.99];player.velocity=[0,0,-2];
  drivePlayerBall(maze,player,.02,0,0);
  assert.equal(player.room,1);assert.ok(Math.abs(dot(player.forward,player.up))<1e-8);
  updateBallCamera(player,.02);
  const saved=importState(exportState(maze,player,[],[]));
  assert.deepEqual(saved.player,player);
  const legacy=importState(exportState(new Maze(),initialPlayer(),[],[]));
  assert.equal(legacy.player.mode,undefined);
});


test('left and right steer by the screen for every gravity axis and a stale control heading',()=>{
  for(const up of normals)for(const forward of normals){
    if(Math.abs(dot(up,forward))>.1)continue;
    for(const side of [-1,1])for(const lag of [1,-1]){
      const player=actor();player.up=[...up];player.cameraUp=[...up];
      player.cameraForward=[...forward];player.forward=mul(forward,-1);
      player.velocity=mul(forward,2*lag);
      const speed=Math.hypot(...player.velocity);
      const desired=mul(norm(cross(forward,up)),side);
      const before=dot(norm(player.velocity),desired);
      steerPlayerBall(player,side,.05);
      assert.ok(dot(norm(player.velocity),desired)>before,'must turn toward the requested screen edge even after a reversal');
      assert.ok(Math.hypot(...player.velocity)<speed);
      assert.ok(Math.hypot(...player.velocity)>speed*.98,'steering loses only a small amount of momentum');
    }
  }
});

test('stationary steering turns the view and forward acceleration uses the view, while S brakes',()=>{
  const maze=new Maze(),player=actor();player.p=[0,-2.5,0];player.velocity=[0,0,0];
  const right=norm(cross(player.cameraForward,player.cameraUp));
  steerPlayerBall(player,-1,.05);
  assert.ok(dot(player.cameraForward,right)<0);
  player.forward=mul(player.cameraForward,-1);
  drivePlayerBall(maze,player,.01,1,0);
  assert.ok(dot(player.velocity,player.cameraForward)>0);
  player.velocity=[1,0,0];player.omega=[0,0,-2];
  drivePlayerBall(maze,player,.01,-1,0);
  assert.ok(player.velocity[0]>0&&player.velocity[0]<1);
});


test('manual ball pitch offsets the automatic motion frame without altering steering or physics',()=>{
  const player=actor();player.cameraForward=[0,0,-1];player.cameraUp=[0,1,0];
  player.pitch=Math.PI/3;
  const baseForward=[...player.cameraForward],velocity=[...player.velocity];
  const view=ballCameraFrame(player);
  assert.ok(view.forward[1]>.8);
  assert.ok(Math.abs(dot(view.forward,view.up))<1e-8);
  assert.deepEqual(player.cameraForward,baseForward);assert.deepEqual(player.velocity,velocity);
  assert.ok(dot(norm(cross(view.forward,view.up)),[1,0,0])>.999999);
  player.cameraForward=[0,-1,0];player.cameraUp=[0,0,-1];player.pitch=89*Math.PI/180;
  const fallingView=ballCameraFrame(player);
  assert.ok(fallingView.forward[2]<-.99,'looking up while falling produces a nearly horizontal view');
});
