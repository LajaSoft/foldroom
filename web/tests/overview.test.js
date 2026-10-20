import test from 'node:test';
import assert from 'node:assert/strict';
import {Maze, MAX_ROOMS, cameraFrame} from '../dist/core.js';
import {initialPlayer, exportState, importState} from '../dist/state.js';
import {overviewCamera, projectionMatrix} from '../dist/overview.js';

test('wheel camera remains inside until it crosses the physical room boundary', () => {
  const maze=new Maze(), frame=cameraFrame(maze,initialPlayer());
  const close=overviewCamera(maze,frame,.5);
  assert.equal(close.outside,false);
  const far=overviewCamera(maze,frame,20);
  assert.equal(far.outside,true);
  assert.ok(Math.abs(Math.hypot(...far.worldEye.map((v,i)=>v-far.anchor[i]))-20)<1e-8);
});

test('large zoom keeps the anchor between near and far clipping planes', () => {
  const projection=projectionMatrix([0,0,300000],[0,0,-1],[0,1,0],[1,0,0],1.5,300000);
  const z=projection[14],w=projection[15];
  assert.ok(w>0 && z/w>-1 && z/w<1);
});

test('10,000 rooms survive JSON roundtrip and reject only the next room', () => {
  const maze=new Maze();
  for(let i=1;i<MAX_ROOMS;i++)maze.room([i,0,0]);
  assert.equal(maze.rooms.length,10000);
  const restored=importState(exportState(maze,initialPlayer(),[],[]));
  assert.equal(restored.maze.rooms.length,10000);
  assert.throws(()=>maze.room([10000,0,0]),/10,000/);
});
