import test from 'node:test';
import assert from 'node:assert/strict';
import {Maze,createBall,moveBall,movePlayer,brakeVector,BALL_BRAKE_SPEED,BALL_MAX_SPEED,HALF} from '../dist/core.js';
import {exportState,importState,initialPlayer} from '../dist/state.js';

test('retrograde braking is gradual, preserves direction and leaves ordinary rolling untouched',()=>{
  assert.deepEqual(brakeVector([1,0,0],.01),[1,0,0]);
  const result=brakeVector([0,0,-1000],.01);
  assert.ok(result[2]<-BALL_BRAKE_SPEED&&result[2]>-1000);
  assert.deepEqual(brakeVector([NaN,0,0],.01),[0,0,0]);
  assert.ok(Math.hypot(...brakeVector([0,0,1e200],.01))<=BALL_MAX_SPEED);
});

test('a falling sphere stays bounded for twenty simulated minutes in a folded gravity loop',()=>{
  const maze=new Maze();
  // Four folds turn a square into a continuously descending local corridor.
  maze.create(0,3,'up',[1,0,0]);
  maze.create(1,0,'up',[0,1,0]);
  maze.create(2,2,'up',[-1,0,0]);
  maze.create(3,1,'up',[0,-1,0]);
  const ball=createBall(0);ball.p=[0,0,0];ball.velocity=[0,-7,0];ball.omega=[0,0,0];
  const rooms=new Set();
  for(let i=0;i<120000;i++){
    moveBall(maze,ball,.01);rooms.add(ball.room);
    assert.ok(Math.hypot(...ball.velocity)<=BALL_MAX_SPEED+1e-9);
    assert.ok(ball.p.every(v=>Number.isFinite(v)&&Math.abs(v)<=HALF+.6));
    assert.ok(Math.abs(Math.hypot(...ball.spin)-1)<1e-6);
  }
  assert.ok(rooms.size>1,'sphere must really cross portals');
});

test('import repairs invalid ball motion and escaped positions while keeping maze and healthy balls',()=>{
  const maze=new Maze(),player=initialPlayer(),healthy=createBall(.4);
  for(const velocity of [[null,0,0], [0,0,3391], 'invalid']){
    const data=JSON.parse(exportState(maze,player,[healthy,createBall()],[]));
    data.balls[1].velocity=velocity;
    const restored=importState(JSON.stringify(data));
    assert.deepEqual(restored.balls[0],healthy);
    assert.deepEqual(restored.balls[1].velocity,[0,0,0]);
  }
  const data=JSON.parse(exportState(maze,player,[healthy,createBall()],[]));
  data.balls[1].p=[1,0,-446255];data.balls[1].omega=[null,0,0];
  const restored=importState(JSON.stringify(data));
  assert.deepEqual(restored.balls[1].velocity,[0,0,0]);
  assert.deepEqual(restored.balls[1].omega,[0,0,0]);
  assert.ok(restored.balls[1].p.every(v=>Math.abs(v)<HALF));
  data.player.p=[null,0,0];
  assert.throws(()=>importState(JSON.stringify(data)),/vector/);
});


test('balls and player cross many folded rooms in one frame at the hard limit without escaping',()=>{
  const maze=new Maze();
  maze.create(0,3,'up',[1,0,0]);
  maze.create(1,0,'up',[0,1,0]);
  maze.create(2,2,'up',[-1,0,0]);
  maze.create(3,1,'up',[0,-1,0]);
  const ball=createBall(0);ball.p=[0,0,0];ball.omega=[0,0,0];
  const player=initialPlayer();player.p=[0,0,0];player.forward=[0,0,-1];
  for(let i=0;i<200;i++){
    ball.velocity=ball.up.map(v=>-v*BALL_MAX_SPEED);
    player.velocity=player.up.map(v=>-v*BALL_MAX_SPEED);
    moveBall(maze,ball,.05);movePlayer(maze,player,.05,0,0);
    for(const actor of [ball,player]){
      assert.ok(actor.p.every(v=>Number.isFinite(v)&&Math.abs(v)<=HALF+.2));
      assert.ok(Math.hypot(...actor.velocity)<=BALL_MAX_SPEED+1e-8);
    }
  }
});

test('player free fall for a minute remains fast and finite through the loop',()=>{
  const maze=new Maze();
  maze.create(0,3,'up',[1,0,0]);maze.create(1,0,'up',[0,1,0]);
  maze.create(2,2,'up',[-1,0,0]);maze.create(3,1,'up',[0,-1,0]);
  const player=initialPlayer();player.p=[0,0,0];player.forward=[0,0,-1];
  for(let i=0;i<6000;i++)movePlayer(maze,player,.01,0,0);
  assert.ok(Math.hypot(...player.velocity)>450);
  assert.ok(player.p.every(v=>Number.isFinite(v)&&Math.abs(v)<=HALF+.2));
});
