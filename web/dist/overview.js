import {add, sub, mul, dot} from './core.js';

export const overviewVertex = `#version 300 es
precision highp float;
layout(location=0) in vec2 corner;
layout(location=1) in vec3 cellCenter;
layout(location=2) in vec3 faceData;
uniform mat4 projection;
out vec2 uv;
flat out int face;
flat out vec2 metadata;
void main(){
 face=int(faceData.x+.5);metadata=faceData.yz;uv=corner*.5+.5;
 float sign=face%2==0?1.:-1.;vec3 p;
 if(face<2)p=vec3(sign*3.,corner.y*3.,corner.x*3.);
 else if(face<4)p=vec3(corner.x*3.,sign*3.,corner.y*3.);
 else p=vec3(corner.x*3.,corner.y*3.,sign*3.);
 gl_Position=projection*vec4(p+cellCenter,1.);
}`;
export const overviewFragment = `#version 300 es
precision highp float;
precision highp int;
in vec2 uv;
flat in int face;
flat in vec2 metadata;
uniform sampler2D markings;
out vec4 color;
vec3 faceColor(int f){if(f==0)return vec3(.92,.41,.38);if(f==1)return vec3(.33,.78,.69);if(f==2)return vec3(.85,.83,.73);if(f==3)return vec3(.39,.55,.88);if(f==4)return vec3(.69,.51,.83);return vec3(.93,.67,.38);}
void main(){
 vec2 edge=min(uv,1.-uv);float border=min(edge.x,edge.y);
 if(metadata.x>.5&&border>.013)discard;
 float rim=1.-smoothstep(.008,.018,border);
 vec2 grid=abs(fract(uv*3.-.5)-.5)/max(fwidth(uv*3.),vec2(.002));
 float lines=1.-min(min(grid.x,grid.y),1.);
 vec3 base=faceColor(face)*(.68+rim*.65+lines*.15);
 float alpha=.2+rim*.28;
 if(metadata.x>.5){base=mix(vec3(.8,.98,.88),vec3(1.,.82,.38),step(1.5,metadata.x));alpha=.72;}
 if(metadata.y>.5){float slot=metadata.y-1.;vec2 tile=vec2(mod(slot,16.),floor(slot/16.));vec4 ink=texture(markings,(tile*128.+uv*127.+.5)/vec2(2048.,1024.));base=mix(base,ink.rgb,ink.a);alpha=mix(alpha,.85,ink.a);}
 color=vec4(base,alpha);
}`;
export const sphereVertex = `#version 300 es
precision highp float;
layout(location=0) in vec3 localPosition;
uniform mat4 projection;
uniform vec3 center;
uniform float radius;
out vec3 normal;
void main(){normal=localPosition;gl_Position=projection*vec4(center+localPosition*radius,1.);}`;
export const sphereFragment = `#version 300 es
precision highp float;
in vec3 normal;
uniform vec4 spin;
uniform vec3 tint;
uniform vec3 localUp;
uniform float isPlayer;
out vec4 color;
vec3 turn(vec3 p,vec4 q){return p+2.*cross(q.xyz,cross(q.xyz,p)+q.w*p);}
void main(){vec3 n=normalize(normal);vec3 local=turn(n,vec4(-spin.xyz,spin.w));float light=.4+.6*max(0.,dot(n,normalize(localUp+vec3(.3,.2,.5))));vec3 c=tint*light;float band=1.-smoothstep(.12,.16,abs(local.y));c=mix(c,vec3(.12,.16,.15),band*(1.-isPlayer));float glint=pow(max(0.,dot(n,normalize(vec3(.3,1.,.6)))),35.);color=vec4(c+glint*.65+isPlayer*.17,1.);}`;

export function projectionMatrix(eye, forward, up, right, aspect, distance) {
  const tangent = .72;
  const near = Math.max(.03, distance * .0001);
  const far = Math.max(10000, distance * 5 + 120000);
  const x = mul(right, 1 / (tangent * aspect)), y = mul(up, 1 / tangent);
  const factor = (far + near) / (far - near), z = mul(forward, factor);
  return new Float32Array([
    x[0], y[0], z[0], forward[0],
    x[1], y[1], z[1], forward[1],
    x[2], y[2], z[2], forward[2],
    -dot(x, eye), -dot(y, eye), -dot(z, eye) - 2 * far * near / (far - near), -dot(forward, eye),
  ]);
}

export function overviewCamera(maze, frame, distance) {
  const anchor = add(mul(maze.rooms[frame.room].cell, 6), frame.p);
  const eye = sub(anchor, mul(frame.forward, distance));
  const cell = eye.map(value => Math.floor((value + 3) / 6));
  const room = maze.cells.get(cell.join(','));
  return {...frame, anchor, worldEye: eye, outside: room === undefined, room: room ?? frame.room,
    p: room === undefined ? frame.p : sub(eye, mul(cell, 6))};
}

export class OverviewRenderer {
  constructor(gl, createProgram) {
    this.gl = gl;
    this.faces = createProgram(overviewVertex, overviewFragment);
    this.spheres = createProgram(sphereVertex, sphereFragment);
    this.faceUniforms = Object.fromEntries(['projection','markings'].map(name => [name, gl.getUniformLocation(this.faces, name)]));
    this.sphereUniforms = Object.fromEntries(['projection','center','radius','spin','tint','localUp','isPlayer'].map(name => [name, gl.getUniformLocation(this.spheres, name)]));
    this.faceVAO = gl.createVertexArray();gl.bindVertexArray(this.faceVAO);
    const quad = gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER, quad);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1,1,-1,1,1,-1,-1,1,1,-1,1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,2,gl.FLOAT,false,0,0);
    this.instances = gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.instances);
    for(const [location, offset] of [[1,0],[2,12]]){gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,3,gl.FLOAT,false,24,offset);gl.vertexAttribDivisor(location,1);}
    this.sphereVAO = gl.createVertexArray();gl.bindVertexArray(this.sphereVAO);
    const vertices=[];
    const point=(lat,lon)=>[Math.sin(lat)*Math.cos(lon),Math.cos(lat),Math.sin(lat)*Math.sin(lon)];
    for(let y=0;y<16;y++)for(let x=0;x<24;x++){
      const a=point(y*Math.PI/16,x*Math.PI/12),b=point((y+1)*Math.PI/16,x*Math.PI/12),c=point((y+1)*Math.PI/16,(x+1)*Math.PI/12),d=point(y*Math.PI/16,(x+1)*Math.PI/12);
      vertices.push(...a,...b,...c,...a,...c,...d);
    }
    this.sphereVertices=vertices.length/3;
    const mesh=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,mesh);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(vertices),gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,0,0);
    this.instanceData = new Float32Array(0);
  }
  render(maze, player, balls, view, right, distance) {
    const gl=this.gl;
    const matrix=projectionMatrix(view.worldEye,view.forward,view.up,right,gl.canvas.width/gl.canvas.height,distance);
    gl.clearColor(.035,.055,.060,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST);gl.depthMask(true);gl.disable(gl.BLEND);
    gl.useProgram(this.spheres);gl.bindVertexArray(this.sphereVAO);const u=this.sphereUniforms;
    gl.uniformMatrix4fv(u.projection,false,matrix);
    const draw=(room,p,radius,spin,up,isPlayer)=>{
      gl.uniform3fv(u.center,add(mul(maze.rooms[room].cell,6),p));gl.uniform1f(u.radius,radius);gl.uniform4fv(u.spin,spin);gl.uniform3fv(u.localUp,up);gl.uniform1f(u.isPlayer,isPlayer);gl.uniform3fv(u.tint,isPlayer?[1,.85,.4]:[.84,.89,.87]);gl.drawArrays(gl.TRIANGLES,0,this.sphereVertices);
    };
    for(const ball of balls)draw(ball.room,ball.p,ball.radius,ball.spin,ball.up,0);
    draw(player.room,player.p,player.mode==='ball'?.5:.28,player.spin??[0,0,0,1],player.up,1);
    // Transparent faces are sorted back-to-front; opaque spheres write depth first.
    const sorted=maze.rooms.map(room=>({room,distance:dot(sub(mul(room.cell,6),view.worldEye),view.forward)})).sort((a,b)=>b.distance-a.distance);
    const needed=maze.rooms.length*36;
    if(this.instanceData.length<needed)this.instanceData=new Float32Array(needed);
    let index=0;
    for(const {room} of sorted)for(let face=0;face<6;face++){
      const link=room.links[face];
      this.instanceData.set([...mul(room.cell,6),face,link?(link.kind==='straight'?1:2):0,room.markers[face]+1],index);index+=6;
    }
    gl.useProgram(this.faces);gl.bindVertexArray(this.faceVAO);gl.bindBuffer(gl.ARRAY_BUFFER,this.instances);
    gl.bufferData(gl.ARRAY_BUFFER,this.instanceData.subarray(0,needed),gl.DYNAMIC_DRAW);
    gl.uniformMatrix4fv(this.faceUniforms.projection,false,matrix);gl.uniform1i(this.faceUniforms.markings,1);
    gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.depthMask(false);
    gl.drawArraysInstanced(gl.TRIANGLES,0,6,maze.rooms.length*6);
    gl.depthMask(true);gl.disable(gl.BLEND);gl.disable(gl.DEPTH_TEST);
  }
}

// Shared exponential dolly for wheel and pinch. Zero is first-person view.
export function zoomCameraDistance(distance,delta) {
  const next=Math.max(0,Math.min(300000,(distance+3)*Math.exp(Math.max(-1,Math.min(1,delta*.002)))-3));
  return next<.03?0:next;
}
