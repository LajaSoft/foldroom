import test from 'node:test';
import assert from 'node:assert/strict';
import {
  Maze, normals, dot, rotate, inverse, faceOf, add, mul, norm, cross, intersect
}
from '../dist/core.js';
const near=(a,b)=>a.forEach((v,i)=>assert.ok(Math.abs(v-b[i])<1e-8,`${a} != ${b}`));
test('all 24 local wall/up orientations: straight/up/down transports are reversible',()=> {
  for(const up of normals)for(let face=0;face<6;face++) {
    if(dot(up,normals[face]))continue;   for(const kind of ['straight','up','down']) {
      const maze=new Maze();const link=maze.create(0,face,kind,up);    const p=add(mul(normals[face],3.04),mul(up,-2));    const direction=norm(add(normals[face],mul(cross(normals[face],up),.17)));    const out=maze.transport(0,face,p,[direction,up]);    const back=maze.transport(out.room,link.face,out.p,out.vectors);    near(back.p,p);near(back.vectors[0],direction);near(back.vectors[1],up);    near(rotate(rotate(up,link.q),inverse(link.q)),up);    assert.equal(back.room,0);assert.equal(maze.passages,1);    const targetDirection=kind==='straight'?normals[face]:mul(up,kind==='up'?1:-1);    near(maze.rooms[out.room].cell,targetDirection);    near(rotate(normals[face],link.q),targetDirection);
    }
  }
}
);
test('backside of a folded wall rejects straight but permits its own fold',()=> {
  const maze=new Maze();maze.create(0,0,'up',[0,1,0]);const other=maze.room([1,0,0]);  assert.throws(()=>maze.create(other.id,1,'straight',[0,1,0]),/only allows an upward/);  maze.create(other.id,1,'down',[0,1,0]);assert.equal(maze.passages,2);
}
);
test('removal closes both endpoints and releases boundary restrictions',()=> {
  const maze=new Maze();const link=maze.create(0,0,'up',[0,1,0]);assert.equal(maze.remove(link.target,link.face),true);assert.equal(maze.rooms[0].links[0],null);assert.equal(maze.walls.size,0);assert.equal(maze.passages,0);maze.create(0,0,'straight',[0,1,0]);
}
);
test('occupied exits cannot be overwritten and no orphan rooms are added',()=> {
  const maze=new Maze();maze.create(0,0,'up',[0,1,0]);const count=maze.rooms.length;assert.throws(()=>maze.create(0,4,'up',[0,1,0]),/occup/);assert.equal(maze.rooms.length,count);assert.equal(maze.passages,1);
}
);
test('grid loops reuse existing room identity',()=> {
  const maze=new Maze();let r=0;for(const f of [0,4,1,5])r=maze.create(r,f,'straight',[0,1,0]).target;assert.equal(r,0);assert.equal(maze.rooms.length,4);assert.equal(maze.passages,4);
}
);
test('ray targeting chooses nearest forward cube boundary',()=> {
  assert.equal(intersect([0,-1.35,0],[0,0,-1]).face,5);  near(intersect([0,0,0],[1,0,0]).point,[3,0,0]);
}
);
test('walking crosses all portal types at floor level and walks back',async()=> {
  const {
    movePlayer
  }
  =await import('../dist/core.js');  for(const up of normals)for(let face=0;face<6;face++) {
    if(dot(up,normals[face]))continue;   for(const kind of ['straight','up','down']) {
      const maze=new Maze();maze.create(0,face,kind,up);    const player= {
        room:0,p:add(mul(up,-2),mul(normals[face],2)),forward:[...normals[face]],up:[...up],velocity:[0,0,0]
      }
      ;    for(let i=0;i<80;i++)movePlayer(maze,player,.01,1,0);    assert.equal(player.room,1,`failed entry ${face} ${up} ${kind}`);    near(player.up,rotate(up,maze.rooms[0].links[face].q));    for(let i=0;i<80;i++)movePlayer(maze,player,.01,-1,0);    assert.equal(player.room,0,`failed return ${face} ${up} ${kind}`);    near(player.up,up);
    }
  }
}
);
test('closed wall blocks movement and closed floor supports the player',async()=> {
  const {
    movePlayer
  }
  =await import('../dist/core.js');const maze=new Maze();  const player= {
    room:0,p:[0,-2,0],forward:[1,0,0],up:[0,1,0],velocity:[0,0,0]
  }
  ;  for(let i=0;i<500;i++)movePlayer(maze,player,.01,1,0);  near(player.p,[2.68,-2,0]);assert.equal(player.room,0);
}
);
test('a previously opened straight passage becomes a fall-through floor',async()=> {
  const {
    movePlayer,cameraFrame
  }
  =await import('../dist/core.js');const maze=new Maze();  maze.create(0,3,'straight',[1,0,0]);  const player= {
    room:0,p:[0,-2,0],forward:[0,0,-1],up:[0,1,0],velocity:[0,0,0]
  }
  ;  let testedStraddling=false;  for(let i=0;i<90;i++) {
    movePlayer(maze,player,.01,0,0);   if(player.room===1 && player.p[1]>2.35) {
      const camera=cameraFrame(maze,player);assert.equal(camera.room,0);assert.ok(camera.p[1]>=-3);testedStraddling=true;
    }
  }
  assert.equal(player.room,1);near(player.up,[0,1,0]);assert.ok(testedStraddling);
}
);
test('powered sphere gains rolling speed and stays slower than walking',async()=> {
  const {
    createBall,moveBall
  }
  =await import('../dist/core.js');const maze=new Maze();  for(let i=0;i<8;i++)maze.create(i,0,'straight',[0,1,0]);  const ball=createBall(0);ball.velocity=[0,0,0];ball.omega=[0,0,0];  for(let i=0;i<1500;i++)moveBall(maze,ball,.01);  const speed=Math.hypot(ball.velocity[0],ball.velocity[2]);assert.ok(speed>.5&&speed<2.6,`rolling speed ${speed}`);assert.ok(ball.room>0);near(ball.up,[0,1,0]);
}
);
test('sphere rebounds from a solid wall',async()=> {
  const {
    createBall,moveBall
  }
  =await import('../dist/core.js');const maze=new Maze();const ball=createBall(0);ball.p=[2.49,-2.5,0];ball.velocity=[1.2,0,0];  for(let i=0;i<5;i++)moveBall(maze,ball,.01);  assert.ok(ball.velocity[0]<0);assert.ok(ball.p[0]<=2.5);
}
);
test('sphere rotates its own gravity and spin through a fold',async()=> {
  const {
    createBall,moveBall
  }
  =await import('../dist/core.js');const maze=new Maze();const link=maze.create(0,0,'up',[0,1,0]);const ball=createBall(0);ball.p=[2.4,-2.5,0];  for(let i=0;i<100;i++)moveBall(maze,ball,.01);  assert.equal(ball.room,1);near(ball.up,rotate([0,1,0],link.q));assert.ok(Math.abs(Math.hypot(...ball.spin)-1)<1e-8);
}
);
test('motor preserves rolling after repeated oblique wall collisions',async()=> {
  const {
    createBall,moveBall
  }
  =await import('../dist/core.js');const maze=new Maze();const ball=createBall(.2);  let slowFrames=0;  for(let i=0;i<30000;i++) {
    moveBall(maze,ball,.01);if(i>20000&&Math.hypot(...ball.velocity)<.05)slowFrames++;
  }
  assert.ok(slowFrames<500,`Motor stalled for ${slowFrames} frames`);
}
);

test('free look tilts the camera while walking and gravity remain horizontal', async () => {
  const {cameraFrame, movePlayer} = await import('../dist/core.js');
  const maze = new Maze();
  for (const pitch of [-89, -45, 0, 45, 89]) {
    const player = {room: 0, p: [0, -2, 0], forward: [0, 0, -1], up: [0, 1, 0], velocity: [0, 0, 0], pitch: pitch * Math.PI / 180};
    const view = cameraFrame(maze, player);
    near(view.forward, [0, Math.sin(player.pitch), -Math.cos(player.pitch)]);
    near(view.gravityUp, [0, 1, 0]);
    assert.ok(Math.abs(dot(view.forward, view.up)) < 1e-8);
    near(cross(view.forward, view.up), [1, 0, 0]);
    movePlayer(maze, player, .01, 1, 0);
    near(player.p, [0, -2, -.026]);
    assert.equal(maze.passages, 0);
  }
});

test('folds preserve free-look pitch relative to the new gravity frame', async () => {
  const {cameraFrame, movePlayer} = await import('../dist/core.js');
  for (const kind of ['up', 'down']) {
    const maze = new Maze();
    const link = maze.create(0, 0, kind, [0, 1, 0]);
    const player = {room: 0, p: [2, -2, 0], forward: [1, 0, 0], up: [0, 1, 0], velocity: [0, 0, 0], pitch: .7};
    const before = cameraFrame(maze, player);
    for (let i = 0; i < 80; i++) movePlayer(maze, player, .01, 1, 0);
    const after = cameraFrame(maze, player);
    assert.equal(player.room, 1);
    near(after.forward, rotate(before.forward, link.q));
    near(after.up, rotate(before.up, link.q));
    near(after.gravityUp, player.up);
    assert.ok(Math.abs(dot(after.forward, after.gravityUp) - Math.sin(.7)) < 1e-8);
  }
});
