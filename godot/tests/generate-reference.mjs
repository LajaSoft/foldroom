import {writeFileSync} from 'node:fs';
import {Maze, normals, createBall, moveBall, movePlayer, add, mul, cross, norm} from '../../web/dist/core.js';
import {drivePlayerBall, updateBallCamera, setPlayerMode, resolveSphereContacts} from '../../web/dist/player-ball.js';
import {initialPlayer, exportState} from '../../web/dist/state.js';

const transport = [];
for (const up of normals) for (let face=0;face<6;face++) {
  if (Math.abs(normals[face].reduce((s,v,i)=>s+v*up[i],0))>.01) continue;
  for (const kind of ['straight','up','down']) {
    const maze = new Maze();
    const link = maze.create(0,face,kind,up);
    const p=add(mul(normals[face],3.1),mul(up,-.8));
    const vectors=[up,normals[face],norm(cross(up,normals[face]))];
    const result=maze.transport(0,face,p,vectors);
    transport.push({up,face,kind,p,vectors,result,back:maze.transport(result.room,link.face,result.p,result.vectors)});
  }
}
const trajectories=[];
for(const mode of ['walk','ball'])for(const kind of ['straight','up','down'])for(const up of normals){
  const forward=normals.find(n=>Math.abs(n.reduce((s,v,i)=>s+v*up[i],0))<.01);
  const face=normals.indexOf(forward);
  const maze=new Maze();maze.create(0,face,kind,up);
  const player={...initialPlayer(),p:mul(up,-2),forward:[...forward],up:[...up],velocity:[0,0,0],mode:'walk'};
  if(mode==='ball')setPlayerMode(player,'ball');
  const initial=structuredClone(player);
  const frames=[];
  for(let i=0;i<360;i++){
    const throttle=i<180?1:i<240?-1:0,side=i>270?.4:0;
    if(mode==='ball'){drivePlayerBall(maze,player,1/120,throttle,side);updateBallCamera(player,1/120);}
    if(mode==='walk')movePlayer(maze,player,1/120,throttle,side);
    if(i%30===29)frames.push({tick:i+1,player:structuredClone(player)});
  }
  trajectories.push({mode,kind,up,face,initial,frames});
}
const balls=[];
for(const angle of [0,.7,2.2]){
 const maze=new Maze(),ball=createBall(angle),initial=structuredClone(ball),frames=[];
 for(let i=0;i<600;i++){moveBall(maze,ball,1/120);if(i%60===59)frames.push({tick:i+1,ball:structuredClone(ball)});}
 balls.push({initial,frames});
}
const contactMaze=new Maze(),a=createBall(0),b=createBall(0);a.p=[-.4,-2.5,0];b.p=[.4,-2.5,0];a.velocity=[3,0,0];b.velocity=[0,0,0];
const contactInitial=structuredClone([a,b]);resolveSphereContacts([a,b],contactMaze);
const maze=new Maze();maze.create(0,0,'up',[0,1,0]);maze.create(1,4,'down',[0,0,1].map((v,i)=>i===0?1:0));
const player=initialPlayer();setPlayerMode(player,'ball');
writeFileSync(new URL('reference.json',import.meta.url),JSON.stringify({transport,trajectories,balls,contact:{initial:contactInitial,expected:[a,b]},state:exportState(maze,player,[createBall(.7)],[])}));
console.log(`Generated ${transport.length} portal orientations, ${trajectories.length} trajectories, ${balls.length} powered-ball runs and a web JSON state.`);
