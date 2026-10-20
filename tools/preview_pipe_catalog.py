"""Create a separate Blender scene from the exact game fitting fields."""
from pathlib import Path
import importlib.util
import itertools
import numpy as np
import bpy
import bmesh
from mathutils import Vector

root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('foldroom_pipe_builder',root/'tools/build_pipe_catalog.py')
builder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

def surface(mask,n=33):
    coord=np.linspace(-3.,3.,n)
    z,y,x=np.meshgrid(coord,coord,coord,indexing='ij')
    grid=np.stack((x,y,z),axis=-1)
    values=builder.field(mask,grid)
    offsets=((0,0,0),(0,0,1),(0,1,1),(0,1,0),(1,0,0),(1,0,1),(1,1,1),(1,1,0))
    p=np.stack([grid[oz:oz+n-1,oy:oy+n-1,ox:ox+n-1].reshape(-1,3) for oz,oy,ox in offsets],axis=1)
    v=np.stack([values[oz:oz+n-1,oy:oy+n-1,ox:ox+n-1].ravel() for oz,oy,ox in offsets],axis=1)
    triangles=[]
    for tetra in ((0,5,1,6),(0,1,2,6),(0,2,3,6),(0,3,7,6),(0,7,4,6),(0,4,5,6)):
        tv=v[:,tetra];tp=p[:,tetra]
        code=sum((tv[:,i]>0).astype(int)<<i for i in range(4))
        for pattern in range(1,15):
            selection=code==pattern
            if not selection.any():continue
            pts=tp[selection]; vals=tv[selection]
            inside=[i for i in range(4) if pattern>>i&1]
            outside=[i for i in range(4) if not pattern>>i&1]
            def cross(a,b):
                t=vals[:,a]/(vals[:,a]-vals[:,b])
                return pts[:,a]+(pts[:,b]-pts[:,a])*t[:,None]
            if len(inside)==1:
                points=[cross(inside[0],b) for b in outside]
                triangles.append(np.stack(points,axis=1))
            if len(inside)==3:
                points=[cross(outside[0],b) for b in inside]
                triangles.append(np.stack(points,axis=1))
            if len(inside)==2:
                a,b=inside;c,d=outside
                ac,ad,bc,bd=cross(a,c),cross(a,d),cross(b,c),cross(b,d)
                triangles.extend((np.stack((ac,ad,bd),axis=1),np.stack((ac,bd,bc),axis=1)))
    triangles=np.concatenate(triangles)
    # A cutaway shows the actual lumen and collars, not just an opaque shell.
    triangles=triangles[triangles.mean(axis=1)[:,2]<0.35]
    vertices=triangles.reshape(-1,3)
    vertices=np.stack((vertices[:,0],-vertices[:,2],vertices[:,1]),axis=1)
    faces=np.arange(len(vertices)).reshape(-1,3)
    return vertices.tolist(),faces.tolist()

scene=bpy.data.scenes.new('FoldRoom - thin pipe fitting catalogue')
scene.render.engine='BLENDER_WORKBENCH'
scene.render.resolution_x=1440
scene.render.resolution_y=900
scene.render.resolution_percentage=100
scene.display.shading.light='STUDIO'
scene.display.shading.color_type='MATERIAL'
scene.display.shading.show_shadows=True
scene.display.shading.show_cavity=True
scene.display.shading.cavity_type='BOTH'
scene.display.shading.background_type='WORLD'
scene.world=bpy.data.worlds.new('FoldRoom catalogue world')
scene.world.color=(.075,.075,.075)
colors=((.8,.32,.25,1),(.3,.7,.6,1),(.8,.75,.5,1),(.32,.5,.8,1),(.65,.45,.8,1))
for index,(mask,name) in enumerate(builder.NAMES.items()):
    verts,faces=surface(mask)
    mesh=bpy.data.meshes.new('fitting_%02d_surface'%mask)
    mesh.from_pydata(verts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new('%02d %s'%(mask,name),mesh)
    scene.collection.objects.link(obj)
    obj.location=(index%5*9,index//5*11,0)
    mat=bpy.data.materials.new('pipe material '+name)
    mat.diffuse_color=colors[index%5]
    obj.data.materials.append(mat)
    for face in mesh.polygons:face.use_smooth=True
    text=bpy.data.curves.new('label '+name,'FONT');text.body=name.replace('_',' ');text.size=.55;text.align_x='CENTER'
    label=bpy.data.objects.new('label '+name,text);scene.collection.objects.link(label)
    label.location=(obj.location.x,obj.location.y-4,-2)
cam_data=bpy.data.cameras.new('catalogue camera');cam=bpy.data.objects.new('catalogue camera',cam_data)
scene.collection.objects.link(cam);scene.camera=cam
cam.location=(20,-34,42);target=Vector((18,5,0));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=49
if bpy.context.window:
    bpy.context.window.scene=scene
out=root/'docs/models';out.mkdir(parents=True,exist_ok=True)
bpy.data.libraries.write(str(out/'pipe-catalog.blend'),{scene},fake_user=True)
scene.render.filepath=str(out/'pipe-catalog.png')
bpy.ops.render.render(write_still=True,scene=scene.name)
print('FoldRoom catalogue created: 10 canonical forms, radius 1.65, sphere radius 0.33')
