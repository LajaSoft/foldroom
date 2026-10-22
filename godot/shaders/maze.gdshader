shader_type canvas_item;
render_mode unshaded;
uniform vec2 resolution;
uniform vec3 eye;
uniform vec3 forward;
uniform vec3 up;
uniform vec3 right;
uniform vec3 gravityUp;
uniform int roomId;
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
float tubeClearance(int room, vec3 p){
 vec2 shape=texelFetch(room_shapes,ivec2(room%1024,room/1024),0).rg;
 int mask=int(shape.r+.5);
 vec3 grid=clamp((p+vec3(3.6))/7.2*48.,vec3(0.),vec3(47.99999));
 int z=int(floor(grid.z));
 float clearance=mix(pipeSlice(mask,z,grid.xy),pipeSlice(mask,z+1,grid.xy),fract(grid.z));
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
 vec3 p=eye;int room=roomId;float distance=0.;vec3 color=vec3(.035,.055,.060);float rim=0.;
 for(int hop=0;hop<64;hop++){
   vec3 safeRay=vec3(abs(ray.x)<.000001?.000001:ray.x,abs(ray.y)<.000001?.000001:ray.y,abs(ray.z)<.000001?.000001:ray.z);
   vec3 t=(sign(safeRay)*3.-p)/safeRay;
   float travel=min(t.x,min(t.y,t.z));
   int axis=t.x<=t.y&&t.x<=t.z?0:(t.y<=t.z?1:2);
   int face=axis*2+(ray[axis]<0.?1:0);
   bool tubeWall=false;
   if(tubes){
    float along=0.;
    for(int step=0;step<256;step++){
     float gap=tubeClearance(room,p+ray*along);
     if(gap<.001){tubeWall=true;travel=along;break;}
     along+=gap*.5;
     if(along>=travel)break;
     // Exhausted grazing rays terminate on the near surface, never behind it.
     if(step==255){tubeWall=true;travel=along;}
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
   if(!tubeWall && data.x>.5 && (tubes || border>.008)){
     rim+=exp(-border*150.)*.2;
     vec4 q=roomData(room,face*2+1);
     ballLight=turn(ballLight,q);
     int destFace=int(data.y+.5);
     ray=turn(ray,q);p=turn(hit-normalOf(face)*3.,q)+normalOf(destFace)*3.+ray*(tubes?.00001:.001);
     room=int(data.x+.5)-1;continue;
   }
   if(tubeWall){
     vec3 e=vec3(.03,0.,0.);
     vec3 n=-normalize(vec3(tubeClearance(room,hit+e.xyy)-tubeClearance(room,hit-e.xyy),tubeClearance(room,hit+e.yxy)-tubeClearance(room,hit-e.yxy),tubeClearance(room,hit+e.yyx)-tubeClearance(room,hit-e.yyx)));
     vec2 ribs=tubeRibs(room,hit,n);
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
   float joint=smoothstep(.0015,.007,border);
   float ao=.62+.38*smoothstep(0.,.19,border);
   float light=.65+.20*dot(-normalOf(face),normalize(vec3(-.4,-.8,.3)));
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
   if(data.x>.5) color=mix(vec3(.72,.88,.81),vec3(.99,.82,.42),step(1.5,data.w))*.9;
   if(data.z>.5){
     float slot=data.z-1.;vec2 tile=vec2(mod(slot,16.),floor(slot/16.));
     vec4 ink=texture(markings,(tile*128.+clamp(uv,0.,1.)*127.+.5)/vec2(2048.,1024.));
     color=mix(color,ink.rgb,ink.a);
   }
   float fog=1.-exp(-distance*.012);
   color=mix(color,vec3(.07,.105,.12),fog);
   break;
 }
 color+=rim*vec3(.11,.15,.13);
 float grain=fract(sin(dot((vec2(UV.x,1.0-UV.y)*resolution),vec2(12.9898,78.233)))*43758.5453)-.5;
 color+=grain*.009;
 COLOR=vec4(pow(max(color,0.),vec3(.88)),1.);
}
