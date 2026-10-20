"""Build the ten symmetry classes of six-face pipe fittings (NumPy only)."""
from pathlib import Path
import gzip
import itertools
import json
import math
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RESOLUTION = 49
EXTENT = 3.6
RADIUS = 1.65
NORMALS = np.array(((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)), dtype=float)
NAMES = {0: 'isolated', 1: 'end_cap', 3: 'straight', 5: 'elbow', 7: 'tee', 15: 'cross', 21: 'trihedral', 23: 'spatial_four_way', 31: 'five_way', 63: 'six_way'}

def symmetry_classes():
    transforms = []
    for axes in itertools.permutations(range(3)):
        for signs in itertools.product((-1,1), repeat=3):
            matrix = np.eye(3)[list(axes)] * np.array(signs)[:,None]
            mapping = [next(i for i,n in enumerate(NORMALS) if np.array_equal(matrix @ v,n)) for v in NORMALS]
            transforms.append((matrix,mapping))
    result = {}
    for mask in range(64):
        candidates = [(sum(1 << mapping[i] for i in range(6) if mask >> i & 1), matrix) for matrix,mapping in transforms]
        canonical, matrix = min(candidates, key=lambda item: item[0])
        result[mask] = {'canonical':canonical, 'to_canonical':matrix.astype(int).tolist()}
    return result

def bend_distance(points, first, second):
    corner = (first+second)*3.0
    offset = points-corner
    planar = np.minimum(offset@first,0)[...,None]*first + np.minimum(offset@second,0)[...,None]*second
    length = np.linalg.norm(planar,axis=-1)
    direction = planar / np.maximum(length,1e-12)[...,None]
    direction = np.where((length<1e-12)[...,None], -first, direction)
    return np.linalg.norm(points-(corner+direction*3.0),axis=-1)

def field(mask, points):
    faces = [i for i in range(6) if mask >> i & 1]
    axes = {i//2 for i in faces}
    if not faces:
        return RADIUS - np.linalg.norm(points,axis=-1)
    if len(faces)==2 and len(axes)==2:
        return RADIUS-bend_distance(points,NORMALS[faces[0]],NORMALS[faces[1]])
    else:
        distances=[]
        for axis in sorted(axes):
            radial=points.copy()
            radial[...,axis]=0
            if axis*2 not in faces:
                radial[...,axis]=np.maximum(points[...,axis],0)
            if axis*2+1 not in faces:
                radial[...,axis]=np.minimum(points[...,axis],0)
            distances.append(np.linalg.norm(radial,axis=-1))
        if len(faces)>=3:
            for i,j in itertools.combinations(faces,2):
                if i//2!=j//2:
                    distances.append(bend_distance(points,NORMALS[i],NORMALS[j]))
        stack=np.stack(distances)
        minimum=stack.min(axis=0)
        # Symmetric blend: the result cannot depend on primitive enumeration.
        distance=minimum-.07*np.log(np.exp((minimum[None]-stack)/.07).sum(axis=0))
        clearance=RADIUS-distance
    # Each fitting terminates in exactly the same round, straight collar.
    # Its shape is independent of its neighbor and of the portal rotation.
    for face in faces:
        n=NORMALS[face]
        axial=points@n
        depth=3.0-axial
        t=np.clip((.9-depth)/.9,0,1)
        weight=t*t*t*(10+t*(-15+6*t))
        radial=points-axial[...,None]*n
        circle=RADIUS-np.linalg.norm(radial,axis=-1)
        clearance=clearance*(1-weight)+circle*weight
    return clearance

def build():
    mapping=symmetry_classes()
    canonical=sorted({v['canonical'] for v in mapping.values()})
    coordinates=np.linspace(-EXTENT,EXTENT,RESOLUTION)
    z,y,x=np.meshgrid(coordinates,coordinates,coordinates,indexing='ij')
    points=np.stack((x,y,z),axis=-1)
    # Store all orientations for two texture reads at runtime, avoiding matrix
    # branches and evaluating any neighboring room in the fragment shader.
    volume=np.empty((64,RESOLUTION,RESOLUTION,RESOLUTION),dtype='<f4')
    for mask in range(64):
        volume[mask]=field(mask,points)
    out=ROOT/'godot/assets/pipes'
    out.mkdir(parents=True,exist_ok=True)
    with gzip.open(out/'catalog.f32.gz','wb',compresslevel=9) as stream:
        stream.write(volume.tobytes())
    manifest={'resolution':RESOLUTION,'extent':EXTENT,'radius':RADIUS,'sphere_radius':.33,'format':'float32 little-endian [mask,z,y,x] gzip','classes':[{'mask':m,'name':NAMES[m],'ports':m.bit_count(),'orientations':sum(v['canonical']==m for v in mapping.values())} for m in canonical],'masks':mapping}
    (out/'catalog.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'classes':len(canonical),'oriented_masks':64,'bytes':volume.nbytes,'compressed_bytes':(out/'catalog.f32.gz').stat().st_size}))

if __name__=='__main__':
    build()
