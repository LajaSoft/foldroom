shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform int face;
uniform sampler2D markings : filter_linear, repeat_disable;
varying vec2 metadata;
void vertex(){metadata=INSTANCE_CUSTOM.xy;}
vec3 faceColor(int f){if(f==0)return vec3(.92,.41,.38);if(f==1)return vec3(.33,.78,.69);if(f==2)return vec3(.85,.83,.73);if(f==3)return vec3(.39,.55,.88);if(f==4)return vec3(.69,.51,.83);return vec3(.93,.67,.38);}
void fragment(){
 vec2 edge=min(UV,1.-UV);float border=min(edge.x,edge.y);
 if(metadata.x>.5&&border>.013)discard;
 float rim=1.-smoothstep(.008,.018,border);
 vec2 grid=abs(fract(UV*3.-.5)-.5)/max(fwidth(UV*3.),vec2(.002));
 float lines=1.-min(min(grid.x,grid.y),1.);
 vec3 base=faceColor(face)*(.68+rim*.65+lines*.15);
 float alpha=.2+rim*.28;
 if(metadata.x>.5){base=mix(vec3(.8,.98,.88),vec3(1.,.82,.38),step(1.5,metadata.x));alpha=.72;}
 if(metadata.y>.5){float slot=metadata.y-1.;vec2 tile=vec2(mod(slot,16.),floor(slot/16.));vec4 ink=texture(markings,(tile*128.+UV*127.+.5)/vec2(2048.,1024.));base=mix(base,ink.rgb,ink.a);alpha=mix(alpha,.85,ink.a);}
 ALBEDO=base;ALPHA=alpha;
}
