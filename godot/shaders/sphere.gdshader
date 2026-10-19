shader_type spatial;
render_mode unshaded;
varying vec3 local_normal;
varying vec3 tint;
void vertex(){local_normal=NORMAL;tint=COLOR.rgb;}
void fragment(){
 vec3 n=normalize(local_normal);
 float light=.4+.6*max(0.,dot(n,normalize(vec3(.3,1.,.5))));
 vec3 c=tint*light;
 float band=1.-smoothstep(.12,.16,abs(n.y));
 c=mix(c,vec3(.12,.16,.15),band);
 float glint=pow(max(0.,dot(n,normalize(vec3(.3,1.,.6)))),35.);
 ALBEDO=c+glint*.65;
}
