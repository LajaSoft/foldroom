shader_type canvas_item;
render_mode unshaded;
uniform vec2 resolution;
uniform vec3 eye;
uniform vec3 forward;
uniform vec3 up;
uniform vec3 right;
uniform vec3 gravityUp;
uniform int roomId;
uniform sampler2D room_zoom : filter_nearest, repeat_disable;
uniform float zoom_coefficient = 1.1;
uniform float actor_scale = 1.0;
uniform float min_zoom = 0.2;
uniform float max_zoom = 4.5;
uniform bool tubes = false;
uniform sampler2D room_shapes : filter_nearest, repeat_disable;
uniform highp sampler2D pipe_catalog : filter_linear, repeat_disable;
uniform sampler2D topology : filter_nearest, repeat_disable;
uniform sampler2D markings : filter_linear, repeat_disable;
uniform float time;
uniform sampler2D balls : filter_nearest, repeat_disable;
uniform int ballCount;

vec4 roomData(int room,int column){int index=room*12+column;return texelFetch(topology,ivec2(index%1024,index/1024),0);}
vec3 normalOf(int f){if(f==0)return vec3(1,0,0);if(f==1)return vec3(-1,0,0);if(f==2)return vec3(0,1,0);if(f==3)return vec3(0,-1,0);if(f==4)return vec3(0,0,1);return vec3(0,0,-1);}
vec3 turn(vec3 p,vec4 q){return p+2.*cross(q.xyz,cross(q.xyz,p)+q.w*p);}
vec2 uvOf(vec3 p,int f){if(f<2)return p.zy/6.+.5;if(f<4)return p.xz/6.+.5;return p.xy/6.+.5;}
vec3 colorOf(int f){if(f==0)return vec3(.92,.41,.38);if(f==1)return vec3(.33,.78,.69);if(f==2)return vec3(.85,.83,.73);if(f==3)return vec3(.39,.55,.88);if(f==4)return vec3(.69,.51,.83);return vec3(.93,.67,.38);}
float passageRatio(int room,int face,float scaleValue){
 int index=room*6+face;
 float step=texelFetch(room_zoom,ivec2(index%1024,index/1024),0).r;
 return clamp(scaleValue*pow(zoom_coefficient,step),min_zoom,max_zoom)/scaleValue;
}
vec3 zoomAnchor(int face,vec3 gravity){
 vec3 n=normalOf(face);
 return -(gravity-n*dot(gravity,n))*(tubes?1.65:3.);
}
float localZoomClearance(int room,vec3 p,vec3 gravity,float scaleValue){
 float gap=100.;
 float radius=3.;
 for(int face=0;face<6;face++){
  float along=dot(p,normalOf(face));
  float ratio=passageRatio(room,face,scaleValue);
  if(ratio<=1.000001||along<=1.5)continue;
  float width=mix(1.,1./ratio,clamp((along-1.5)/1.5,0.,1.));
  vec3 anchor=zoomAnchor(face,gravity);
  vec3 center=anchor*(1.-width);
  float taper=(1.-1./ratio)/1.5;
  for(int a=0;a<3;a++){
   if(a==face/2)continue;
   float upperSlope=(radius-anchor[a])*taper;
   float lowerSlope=(-radius-anchor[a])*taper;
   gap=min(gap,(center[a]+radius*width-p[a])/sqrt(1.+upperSlope*upperSlope));
   gap=min(gap,(p[a]-center[a]+radius*width)/sqrt(1.+lowerSlope*lowerSlope));
  }
 }
 return gap;
}
// Texture metadata keeps driver specialization from unrolling nested queries.
int boxFaceCount(int room){return int(texelFetch(room_shapes,ivec2(room%1024,room/1024),0).a+.5);}
bool boxHasZoom(int room){
 if(texelFetch(room_shapes,ivec2(room%1024,room/1024),0).b>.5)return true;
 for(int face=0;face<boxFaceCount(room);face++){
  vec4 data=roomData(room,face*2);
  if(data.x<.5)continue;
  int dest=int(data.x+.5)-1;
  if(texelFetch(room_shapes,ivec2(dest%1024,dest/1024),0).b>.5)return true;
  for(int next=0;next<boxFaceCount(room);next++){
   vec4 neighbor=roomData(dest,next*2);if(neighbor.x<.5)continue;
   int other=int(neighbor.x+.5)-1;
   if(texelFetch(room_shapes,ivec2(other%1024,other/1024),0).b>.5)return true;
  }
 }
 return false;
}
int faceOf(vec3 n){
 vec3 a=abs(n);int axis=a.x>=a.y&&a.x>=a.z?0:(a.y>=a.z?1:2);
 return axis*2+(n[axis]<0.?1:0);
}
float zoomClearance(int room,vec3 p,vec3 gravity,float scaleValue){
 float gap=localZoomClearance(room,p,gravity,scaleValue);
 for(int face=0;face<boxFaceCount(room);face++){
  if(face!=faceOf(p))continue;
  if(dot(p,normalOf(face))<=1.5)continue;
  vec4 data=roomData(room,face*2);
  if(data.x<.5)continue;
  int dest=int(data.x+.5)-1;
  if(texelFetch(room_shapes,ivec2(dest%1024,dest/1024),0).b<.5)continue;
  vec4 q=roomData(room,face*2+1);
  int destFace=int(data.y+.5);
  float ratio=passageRatio(room,face,scaleValue);
  vec3 anchor=zoomAnchor(face,gravity);
  vec3 mapped=turn(anchor+(p-normalOf(face)*3.-anchor)*ratio,q)+normalOf(destFace)*3.;
  vec3 n=normalOf(destFace);
  vec3 mirrored=mapped-n*2.*(dot(mapped,n)-3.);
  gap=min(gap,localZoomClearance(dest,mirrored,turn(gravity,q),clamp(scaleValue*ratio,min_zoom,max_zoom))/ratio);
 }
 return gap;
}
float localMouthBound(int room,int mouth,int wall,vec3 gravity,float scaleValue){
 float ratio=passageRatio(room,mouth,scaleValue);
 float bound=3.;
 if(ratio>1.000001)bound=3./ratio+dot(normalOf(wall),zoomAnchor(mouth,gravity))*(1.-1./ratio);
 if(passageRatio(room,wall,scaleValue)>1.000001 && 3.-dot(normalOf(mouth),zoomAnchor(wall,gravity))>.000001)bound=min(bound,1.5);
 return bound;
}
float seedSharedMouthBound(int room,int mouth,int wall,vec3 gravity,float scaleValue){
 float bound=localMouthBound(room,mouth,wall,gravity,scaleValue);
 vec4 data=roomData(room,mouth*2);
 if(data.x<.5)return bound;
 vec4 q=roomData(room,mouth*2+1);
 float ratio=passageRatio(room,mouth,scaleValue);
 int dest=int(data.x+.5)-1;
 int destWall=faceOf(turn(normalOf(wall),q));
 float neighbor=localMouthBound(dest,int(data.y+.5),destWall,turn(gravity,q),clamp(scaleValue*ratio,min_zoom,max_zoom));
 float shift=dot(normalOf(wall),zoomAnchor(mouth,gravity))*(1.-ratio);
 return min(bound,(neighbor-shift)/ratio);
}
vec4 seedBoxPlane(int room,int wall,int axis,vec3 gravity,float scaleValue){
 if(roomData(room,wall*2).x>.5)return vec4(0.);
 float positive=seedSharedMouthBound(room,axis*2,wall,gravity,scaleValue);
 float negative=seedSharedMouthBound(room,axis*2+1,wall,gravity,scaleValue);
 float ownPositive=localMouthBound(room,axis*2,wall,gravity,scaleValue);
 float ownNegative=localMouthBound(room,axis*2+1,wall,gravity,scaleValue);
 if(positive>=ownPositive-.000001 && negative>=ownNegative-.000001)return vec4(0.);
 if(min(positive,negative)>=2.999999)return vec4(0.);
 vec3 n=normalOf(wall)+normalOf(axis*2)*(negative-positive)/6.;
 return vec4(n,(positive+negative)*.5)/length(n);
}
float sharedMouthBound(int room,int mouth,int wall,vec3 gravity,float scaleValue){
 float bound=seedSharedMouthBound(room,mouth,wall,gravity,scaleValue);
 vec4 data=roomData(room,mouth*2);
 if(data.x<.5)return bound;
 int dest=int(data.x+.5)-1;int destFace=int(data.y+.5);
 vec4 q=roomData(room,mouth*2+1);
 int destWall=faceOf(turn(normalOf(wall),q));
 float ratio=passageRatio(room,mouth,scaleValue);
 vec3 destGravity=turn(gravity,q);float destScale=clamp(scaleValue*ratio,min_zoom,max_zoom);
 float shift=dot(normalOf(wall),zoomAnchor(mouth,gravity))*(1.-ratio);
 for(int axis=0;axis<boxFaceCount(room)/2;axis++){
  if(axis==destWall/2)continue;
  vec4 plane=seedBoxPlane(dest,destWall,axis,destGravity,destScale);
  float rate=dot(plane.xyz,normalOf(destWall));
  if(rate<=.000001)continue;
  int crossAxis=3-destWall/2-destFace/2;
  float edge=(plane.w-dot(plane.xyz,normalOf(destFace)*3.)-abs(plane[crossAxis])*3.)/rate;
  bound=min(bound,(edge-shift)/ratio);
 }
 return bound;
}
vec4 boxPlane(int room,int wall,int axis,vec3 gravity,float scaleValue){
 if(roomData(room,wall*2).x>.5)return vec4(0.);
 float positive=sharedMouthBound(room,axis*2,wall,gravity,scaleValue);
 float negative=sharedMouthBound(room,axis*2+1,wall,gravity,scaleValue);
 float ownPositive=localMouthBound(room,axis*2,wall,gravity,scaleValue);
 float ownNegative=localMouthBound(room,axis*2+1,wall,gravity,scaleValue);
 if(positive>=ownPositive-.000001 && negative>=ownNegative-.000001)return vec4(0.);
 if(min(positive,negative)>=2.999999)return vec4(0.);
 vec3 n=normalOf(wall)+normalOf(axis*2)*(negative-positive)/6.;
 return vec4(n,(positive+negative)*.5)/length(n);
}
vec3 zoomNormal(int room,vec3 p,vec3 gravity,float scaleValue){
 vec3 e=vec3(.002,0.,0.);
 return -normalize(vec3(zoomClearance(room,p+e.xyy,gravity,scaleValue)-zoomClearance(room,p-e.xyy,gravity,scaleValue),zoomClearance(room,p+e.yxy,gravity,scaleValue)-zoomClearance(room,p-e.yxy,gravity,scaleValue),zoomClearance(room,p+e.yyx,gravity,scaleValue)-zoomClearance(room,p-e.yyx,gravity,scaleValue)));
}
// Smooth aggregate height gradient: bump shading without square color cells.
float aggregateHash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
vec3 aggregateGradient(vec3 p){
 vec3 cell=floor(p),t=fract(p);
 vec3 u=t*t*(3.-2.*t),du=6.*t*(1.-t);
 float a=aggregateHash(cell),b=aggregateHash(cell+vec3(1,0,0));
 float c=aggregateHash(cell+vec3(0,1,0)),d=aggregateHash(cell+vec3(1,1,0));
 float e=aggregateHash(cell+vec3(0,0,1)),f=aggregateHash(cell+vec3(1,0,1));
 float g=aggregateHash(cell+vec3(0,1,1)),h=aggregateHash(cell+vec3(1,1,1));
 return du*vec3(mix(mix(b-a,d-c,u.y),mix(f-e,h-g,u.y),u.z),
                mix(mix(c-a,d-b,u.x),mix(g-e,h-f,u.x),u.z),
                mix(mix(e-a,f-b,u.x),mix(g-c,h-d,u.x),u.y));
}
// Two bilinear reads interpolate a local fitting. Complete straight squares
// additionally open their shared corners, using the same field as physics.
float pipeSlice(int mask,int z,vec2 xy){
 int slice=mask*49+z;
 vec2 pixel=vec2(float(slice%64),float(slice/64))*49.+xy+.5;
 return texture(pipe_catalog,pixel/vec2(3136.,2401.)).r;
}
float bendDistance(vec3 p,vec3 a,vec3 b){
 vec3 corner=(a+b)*3.;
 vec3 offset=p-corner;
 vec3 planar=a*min(dot(offset,a),0.)+b*min(dot(offset,b),0.);
 vec3 direction=dot(planar,planar)>1e-12?normalize(planar):-a;
 return length(p-(corner+direction*3.));
}
float analyticPipe(int mask,vec3 p){
 int count=0,first=-1,second=-1;
 for(int face=0;face<6;face++){
  if((mask & (1<<face))==0)continue;
  if(count==0)first=face;
  if(count==1)second=face;
  count++;
 }
 if(count==0)return 1.65-length(p);
 if(count==2 && first/2!=second/2)return 1.65-bendDistance(p,normalOf(first),normalOf(second));
 float distances[15];int used=0;float minimum=100.;
 for(int axis=0;axis<3;axis++){
  if((mask & (3<<(axis*2)))==0)continue;
  vec3 radial=p;radial[axis]=0.;
  if((mask & (1<<(axis*2)))==0)radial[axis]=max(p[axis],0.);
  if((mask & (1<<(axis*2+1)))==0)radial[axis]=min(p[axis],0.);
  distances[used]=length(radial);minimum=min(minimum,distances[used]);used++;
 }
 if(count>=3){
  for(int a=0;a<6;a++){
   if((mask & (1<<a))==0)continue;
   for(int b=(a/2+1)*2;b<6;b++){
    if((mask & (1<<b))==0)continue;
    distances[used]=bendDistance(p,normalOf(a),normalOf(b));minimum=min(minimum,distances[used]);used++;
   }
  }
 }
 float total=0.;
 for(int i=0;i<15;i++){if(i>=used)break;total+=exp((minimum-distances[i])/.07);}
 float clearance=1.65-minimum+.07*log(total);
 for(int face=0;face<6;face++){
  if((mask & (1<<face))==0)continue;
  vec3 n=normalOf(face);float along=dot(p,n);
  float t=clamp((along-2.1)/.9,0.,1.);
  float weight=t*t*t*(10.+t*(-15.+6.*t));
  clearance=mix(clearance,1.65-length(p-n*along),weight);
 }
 return clearance;
}
float tubeClearance(int room, vec3 p){
 vec2 shape=texelFetch(room_shapes,ivec2(room%1024,room/1024),0).rg;
 int mask=int(shape.r+.5);
 vec3 grid=clamp((p+vec3(3.6))/7.2*48.,vec3(0.),vec3(47.99999));
 int z=int(floor(grid.z));
 float clearance;
 if(texelFetch(room_shapes,ivec2(room%1024,room/1024),0).b>.5)clearance=analyticPipe(mask,p);
 else clearance=mix(pipeSlice(mask,z,grid.xy),pipeSlice(mask,z+1,grid.xy),fract(grid.z));
 int corners=int(shape.g+.5);
 if(corners==0)return clearance;
 int bit=0;
 for(int a=0;a<6;a++){
  for(int b=(a/2+1)*2;b<6;b++){
   if((corners & (1<<bit))!=0){
    int axis=3-a/2-b/2;
    vec3 offset=vec3(min(dot(p,normalOf(a)),0.),min(dot(p,normalOf(b)),0.),p[axis]);
    clearance=max(clearance,1.65-length(offset));
   }
   bit++;
  }
 }
 return clearance;
}

float smoothTaper(float t){
 t=clamp(t,0.,1.);
 return t*t*t*(t*(6.*t-15.)+10.);
}
vec4 tubeDeformation(int room,vec3 p,vec3 gravity,float scaleValue){
 vec3 mapped=p;float metric=1.;
 if(texelFetch(room_shapes,ivec2(room%1024,room/1024),0).b<.5)return vec4(p,metric);
 for(int face=0;face<6;face++){
  float ratio=passageRatio(room,face,scaleValue);
  if(ratio<=1.000001)continue;
  vec3 n=normalOf(face);
  float weight=smoothTaper((dot(p,n)-1.5)/1.5);
  for(int axis=0;axis<3;axis++){
   if(axis!=face/2)weight*=1.-smoothTaper((abs(p[axis])-1.65)/1.35);
  }
  if(weight<=0.)continue;
  float width=mix(1.,1./ratio,weight);
  vec3 anchor=zoomAnchor(face,gravity);
  vec3 axial=n*dot(mapped,n);
  mapped=axial+anchor+(mapped-axial-anchor)/width;
  metric*=width/(1.+6.6*(1.-width));
 }
 return vec4(mapped,metric);
}
float deformedTubeClearance(int room,vec3 p,vec3 gravity,float scaleValue){
 vec4 query=tubeDeformation(room,p,gravity,scaleValue);
 return tubeClearance(room,query.xyz)*query.w;
}

// Twelve longitudinal ribs, invariant under the portals' quarter turns.
// Blend connected arm directions at fittings instead of projecting cross rings.
vec2 tubeRibs(int room,vec3 p,vec3 n){
 int mask=int(texelFetch(room_shapes,ivec2(room%1024,room/1024),0).r+.5);
 vec2 ribs=vec2(0.);
 float total=0.;
 for(int axis=0;axis<3;axis++){
  if((mask & (3<<(axis*2)))==0)continue;
  vec2 radial=axis==0?p.yz:(axis==1?p.zx:p.xy);
  float radius=length(radial);
  float weight=(.15+p[axis]*p[axis])*pow(1.-abs(n[axis]),4.)*smoothstep(.15,.65,radius);
  float angle=atan(radial.y,radial.x+.000001);
  float phase=angle*12.;
  float width=max(fwidth(phase),.001);
  float arc=abs(sin(phase*.5))*2.;
  float visible=1.-smoothstep(.3,.9,width);
  ribs+=vec2(1.-smoothstep(.055,.055+width,arc),1.-smoothstep(.12,.48+width,arc))*weight*visible;
  total+=weight;
 }
 return ribs/max(total,.0001);
}

void fragment(){
 vec2 screen=((vec2(UV.x,1.0-UV.y)*resolution)*2.-resolution)/resolution.y;
 vec3 ray=normalize(forward+right*screen.x*.72+up*screen.y*.72);
 // Keep sphere lighting aligned with the player's floor through every portal.
 vec3 ballLight=normalize(gravityUp);
 vec3 localGravity=gravityUp;float scaleValue=actor_scale;
 vec3 p=eye;int room=roomId;float distance=0.;vec3 color=vec3(.035,.055,.060);
 for(int hop=0;hop<64;hop++){
   vec3 safeRay=vec3(abs(ray.x)<.000001?.000001:ray.x,abs(ray.y)<.000001?.000001:ray.y,abs(ray.z)<.000001?.000001:ray.z);
   vec3 t=(sign(safeRay)*3.-p)/safeRay;
   float travel=min(t.x,min(t.y,t.z));
   int axis=t.x<=t.y&&t.x<=t.z?0:(t.y<=t.z?1:2);
   int face=axis*2+(ray[axis]<0.?1:0);
   bool zoomWall=false;
   bool planeWall=false;vec3 planeNormal=vec3(0.);
   if(!tubes && boxHasZoom(room)){
    for(int wall=0;wall<boxFaceCount(room);wall++){
     if(roomData(room,wall*2).x>.5)continue;
     for(int crossAxis=0;crossAxis<boxFaceCount(room)/2;crossAxis++){
      if(crossAxis==wall/2)continue;
      vec4 plane=boxPlane(room,wall,crossAxis,localGravity,scaleValue);
      vec3 n=plane.xyz;if(dot(n,n)<.5)continue;
      float gap=plane.w-dot(n,p);
      float rate=dot(n,ray);
      if(rate<=.000001 && gap>=0.)continue;
      float t=gap<0.?0.:gap/rate;
      if(t>=0. && t<travel){travel=t;zoomWall=true;planeWall=true;planeNormal=normalize(n);}
     }
    }
   }
   if(!tubes && boxHasZoom(room)){
    for(int mouth=0;mouth<boxFaceCount(room);mouth++){
     vec4 data=roomData(room,mouth*2);if(data.x<.5)continue;
     vec3 sourceNormal=normalOf(mouth);
     float along=dot(p,sourceNormal),speed=dot(ray,sourceNormal);
     float begin=0.,finish=travel;
     if(abs(speed)<.000001){if(along<=1.5)continue;}
     else{
      float edge=(1.5-along)/speed;
      if(speed>0.)begin=max(begin,edge);else finish=min(finish,edge);
     }
     for(int axis=0;axis<boxFaceCount(room)/2;axis++){
      if(axis==mouth/2)continue;
      for(int signIndex=0;signIndex<2;signIndex++){
       float side=signIndex==0?1.:-1.;
       float value=along-side*p[axis],rate=speed-side*ray[axis];
       if(abs(rate)<.000001){if(value<0.)finish=-1.;continue;}
       float edge=-value/rate;
       if(rate>0.)begin=max(begin,edge);else finish=min(finish,edge);
      }
     }
     if(finish<=begin)continue;
     int dest=int(data.x+.5)-1;int destFace=int(data.y+.5);
     vec4 q=roomData(room,mouth*2+1);
     float ratio=passageRatio(room,mouth,scaleValue);
     vec3 anchor=zoomAnchor(mouth,localGravity);
     vec3 n=normalOf(destFace);
     vec3 mapped=turn(anchor+(p-sourceNormal*3.-anchor)*ratio,q)+n*3.;
     vec3 mappedRay=turn(ray*ratio,q);
     mapped-=n*2.*(dot(mapped,n)-3.);mappedRay-=n*2.*dot(mappedRay,n);
     vec3 destGravity=turn(localGravity,q);float destScale=clamp(scaleValue*ratio,min_zoom,max_zoom);
     for(int wall=0;wall<boxFaceCount(room);wall++){
      if(roomData(dest,wall*2).x>.5)continue;
      for(int axis=0;axis<boxFaceCount(room)/2;axis++){
       if(axis==wall/2)continue;
       vec4 plane=boxPlane(dest,wall,axis,destGravity,destScale);
       if(dot(plane.xyz,plane.xyz)<.5)continue;
       float gap=plane.w-dot(plane.xyz,mapped+mappedRay*begin);
       float rate=dot(plane.xyz,mappedRay);
       if(rate<=.000001 && gap>=0.)continue;
       float t=gap<0.?begin:begin+gap/rate;
       if(t<begin || t>=finish || t>=travel)continue;
       vec3 reflected=plane.xyz-n*2.*dot(plane.xyz,n);
       planeNormal=normalize(turn(reflected,vec4(-q.xyz,q.w)));
       travel=t;zoomWall=true;planeWall=true;
      }
     }
    }
   }
   float zoomAlong=0.;
   bool zoomRoom=!tubes && boxHasZoom(room);
   for(int step=0;step<192;step++){
    if(tubes || !zoomRoom)break;
    float gap=zoomClearance(room,p+ray*zoomAlong,localGravity,scaleValue);
    if(gap<.001){zoomWall=true;planeWall=false;travel=zoomAlong;break;}
    zoomAlong+=clamp(gap*.5,.0005,.08);
    if(zoomAlong>=travel)break;
   }
   bool tubeWall=false;
   if(tubes){
    float along=0.;
    for(int step=0;step<256;step++){
     float gap=deformedTubeClearance(room,p+ray*along,localGravity,scaleValue);
     if(gap<.001){zoomWall=false;tubeWall=true;travel=along;break;}
     along+=gap*.5;
     if(along>=travel)break;
     // Exhausted grazing rays terminate on the near surface, never behind it.
     if(step==255){zoomWall=false;tubeWall=true;travel=along;}
    }
   }
   int nearestBall=-1;float nearestDistance=travel;
   for(int ball=0;ball<128;ball++){
     if(ball>=ballCount)break;
     vec4 sphere=texelFetch(balls,ivec2(0,ball),0);
     vec4 frame=texelFetch(balls,ivec2(1,ball),0);
     if(int(frame.w+.5)!=room)continue;
     vec3 offset=p-sphere.xyz;
     float b=dot(offset,ray),c=dot(offset,offset)-sphere.w*sphere.w;
     float discriminant=b*b-c;if(discriminant<0.)continue;
     float entry=-b-sqrt(discriminant);
     float t=entry>.0001?entry:-b+sqrt(discriminant);
     if(t>.0001&&t<nearestDistance){nearestDistance=t;nearestBall=ball;}
   }
   if(nearestBall>=0){
     vec4 sphere=texelFetch(balls,ivec2(0,nearestBall),0);
     vec3 normal=normalize(p+ray*nearestDistance-sphere.xyz);
     vec4 spin=texelFetch(balls,ivec2(2,nearestBall),0);
     vec3 localNormal=turn(normal,vec4(-spin.xyz,spin.w));
     vec3 reflected=reflect(ray,normal);
     int reflectionAxis=abs(reflected.x)>abs(reflected.y)&&abs(reflected.x)>abs(reflected.z)?0:(abs(reflected.y)>abs(reflected.z)?1:2);
     int reflectedFace=reflectionAxis*2+(reflected[reflectionAxis]<0.?1:0);
     float diffuse=.32+.48*max(0.,dot(normal,ballLight));
     float fresnel=pow(1.-max(0.,dot(normal,-ray)),3.);
     vec3 steel=mix(vec3(.72,.77,.77)*diffuse,colorOf(reflectedFace)*.9,.48+fresnel*.35);
     float band=1.-smoothstep(.12,.15,abs(localNormal.y));
     steel=mix(steel,vec3(.19,.23,.22)*(.7+diffuse),band);
     float seam=1.-smoothstep(.009,.02,abs(abs(localNormal.y)-.135));
     steel=mix(steel,vec3(.97,.8,.38),seam);
     float specular=pow(max(0.,dot(reflected,ballLight)),80.);
     color=steel+vec3(1.,.98,.87)*specular*.9;
     color=mix(color,vec3(.07,.105,.12),1.-exp(-(distance+nearestDistance)*.012));
     break;
   }
   vec3 hit=p+ray*max(0.,travel);distance+=max(0.,travel);
   vec2 uv=uvOf(hit,face);vec2 edge=min(uv,1.-uv);float border=min(edge.x,edge.y);
   vec4 data=roomData(room,face*2);
   if(!zoomWall && !tubeWall && data.x>.5){
     vec4 q=roomData(room,face*2+1);
     ballLight=turn(ballLight,q);
     int destFace=int(data.y+.5);
     float ratio=passageRatio(room,face,scaleValue);
     vec3 anchor=zoomAnchor(face,localGravity);
     vec3 mapped=anchor+(hit-normalOf(face)*3.-anchor)*ratio;
     scaleValue=clamp(scaleValue*ratio,min_zoom,max_zoom);
     localGravity=turn(localGravity,q);
     ray=turn(ray,q);p=turn(mapped,q)+normalOf(destFace)*3.+ray*(tubes?.00001:.001);
     room=int(data.x+.5)-1;continue;
   }
   vec3 wallNormal=normalOf(face);
   if(zoomWall){
     wallNormal=planeWall?planeNormal:zoomNormal(room,hit,localGravity,scaleValue);
     int wallAxis=abs(wallNormal.x)>=abs(wallNormal.y)&&abs(wallNormal.x)>=abs(wallNormal.z)?0:(abs(wallNormal.y)>=abs(wallNormal.z)?1:2);
     face=wallAxis*2+(wallNormal[wallAxis]<0.?1:0);
     // A shared mouth cut extends a closed side wall into this approach.
     // Use that side's material instead of painting a ghost portal face.
     float sideScore=.0001;
     for(int side=0;side<6;side++){
      if(roomData(room,side*2).x>.5)continue;
      float score=dot(wallNormal,normalOf(side));
      if(score>sideScore){sideScore=score;face=side;}
     }
     uv=uvOf(hit,face);
     data=vec4(0.);
   }
   if(tubeWall){
     vec3 e=vec3(.03,0.,0.);
     vec3 n=-normalize(vec3(deformedTubeClearance(room,hit+e.xyy,localGravity,scaleValue)-deformedTubeClearance(room,hit-e.xyy,localGravity,scaleValue),deformedTubeClearance(room,hit+e.yxy,localGravity,scaleValue)-deformedTubeClearance(room,hit-e.yxy,localGravity,scaleValue),deformedTubeClearance(room,hit+e.yyx,localGravity,scaleValue)-deformedTubeClearance(room,hit-e.yyx,localGravity,scaleValue)));
     vec4 surfaceQuery=tubeDeformation(room,hit,localGravity,scaleValue);
     vec2 ribs=tubeRibs(room,surfaceQuery.xyz,n);
     // Fade unresolved microrelief to prevent shimmer at grazing angles.
     float detail=1.-smoothstep(.35,1.2,length(fwidth(hit*240.)));
     vec3 gradient=aggregateGradient(hit*240.);
     vec3 bump=normalize(n-(gradient-n*dot(n,gradient))*.32*detail);
     vec3 lamp=normalize(vec3(.4,.8,.3));
     float light=.78+.22*abs(dot(bump,lamp));
     float sheen=pow(max(0.,dot(bump,normalize(lamp-ray))),mix(32.,64.,ribs.y))*mix(.34,.95,ribs.y);
     float facing=1.-max(0.,dot(bump,-ray));
     int panelAxis=abs(n.x)>=abs(n.y)&&abs(n.x)>=abs(n.z)?0:(abs(n.y)>=abs(n.z)?1:2);
     int panelFace=panelAxis*2+(n[panelAxis]<0.?1:0);
     vec3 tint=colorOf(panelFace);
     float luminance=dot(tint,vec3(.2126,.7152,.0722));
     tint=max(vec3(0.),mix(vec3(luminance),tint,1.3));
     vec3 asphalt=mix(vec3(.23,.25,.26),tint*.48,.82);
     asphalt=mix(asphalt,asphalt*1.3+vec3(.025,.035,.04),ribs.x*.65);
     color=asphalt*light+vec3(sheen+.025*pow(facing,3.));
     color=mix(color,vec3(.07,.105,.12),1.-exp(-distance*.012));
     break;
   }
   vec3 base=colorOf(face);
   vec2 grid=abs(fract(uv*12.-.5)-.5)/max(fwidth(uv*12.),vec2(.005));
   float line=1.-min(min(grid.x,grid.y),1.);
   vec2 major=abs(fract(uv*3.-.5)-.5)/max(fwidth(uv*3.),vec2(.003));
   float bigLine=1.-min(min(major.x,major.y),1.);
   float joint=zoomWall?1.:smoothstep(.0015,.007,border);
   float ao=zoomWall?1.:.62+.38*smoothstep(0.,.19,border);
   float light=.65+.20*dot(-wallNormal,normalize(vec3(-.4,-.8,.3)));
   float centerGlow=.17*exp(-length(uv-.5)*2.);
   color=base*(light+centerGlow)*ao;
   color*=1.-line*.13-bigLine*.07;
   for(int ball=0;ball<128;ball++){
     if(ball>=ballCount)break;
     vec4 sphere=texelFetch(balls,ivec2(0,ball),0);
     vec4 frame=texelFetch(balls,ivec2(1,ball),0);
     if(int(frame.w+.5)!=room)continue;
     vec3 delta=sphere.xyz-hit;
     float height=dot(delta,-normalOf(face));
     float radial=length(delta+normalOf(face)*height);
     color*=1.-.42*exp(-radial*radial*2.5)*exp(-max(0.,height-.5)*1.5);
   }
   color=mix(vec3(.085,.12,.13),color,joint);
   vec2 tick=abs(uv-.5);
   float crossMark=(1.-smoothstep(.001,.0025,min(tick.x,tick.y)))*(1.-smoothstep(.017,.023,max(tick.x,tick.y)));
   color=mix(color,base*1.15,crossMark*.65);
   if(data.z>.5){
     float slot=data.z-1.;vec2 tile=vec2(mod(slot,16.),floor(slot/16.));
     vec4 ink=texture(markings,(tile*128.+clamp(uv,0.,1.)*127.+.5)/vec2(2048.,1024.));
     color=mix(color,ink.rgb,ink.a);
   }
   float fog=1.-exp(-distance*.012);
   color=mix(color,vec3(.07,.105,.12),fog);
   break;
 }
 float grain=fract(sin(dot((vec2(UV.x,1.0-UV.y)*resolution),vec2(12.9898,78.233)))*43758.5453)-.5;
 color+=grain*.009;
 COLOR=vec4(pow(max(color,0.),vec3(.88)),1.);
}
