import {Maze, MAX_ROOMS, HALF, BALL_MAX_SPEED, BALL_MAX_SPIN, add, mul, dot, normals, rotationBetween, inverse} from './core.js';

const requireValue = (condition, message) => {
  if (!condition) throw new Error(message);
};
const same = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 1e-6);
const vector = (value, length, limit = 1e6) => {
  requireValue(Array.isArray(value) && value.length === length && value.every(v => Number.isFinite(v) && Math.abs(v) <= limit), 'Invalid vector in JSON');
  return [...value];
};
const unit = value => {
  const result = vector(value, 3);
  requireValue(Math.abs(Math.hypot(...result) - 1) < 1e-5, 'Invalid orientation');
  return result;
};

export function initialPlayer() {
  const length = Math.hypot(.18, 1);
  return {room: 0, p: [0, -2, 1.1], forward: [.18 / length, 0, -1 / length], up: [0, 1, 0], velocity: [0, 0, 0], pitch: 0};
}

export function exportState(maze, player, balls, marks) {
  const passages = [];
  const seen = new Set();
  for (const room of maze.rooms) {
    room.links.forEach((link, face) => {
      if (!link || seen.has(link.id)) return;
      seen.add(link.id);
      passages.push({a: [room.id, face], b: [link.target, link.face], kind: link.kind});
    });
  }
  return JSON.stringify({format: 'foldroom', version: 1, rooms: maze.rooms.map(room => ({cell: room.cell, markers: room.markers})), passages, player, balls, marks}, null, 2);
}

export function importState(text) {
  requireValue(typeof text === 'string' && text.length <= 16 * 1024 * 1024, 'JSON too large: maximum 16 MB');
  let data;
  try { data = JSON.parse(text); } catch { throw new Error('Could not read JSON. Check the brackets and quotation marks.'); }
  requireValue(data?.format === 'foldroom' && data.version === 1, 'A FOLDROOM version 1 export is required');
  requireValue(Array.isArray(data.rooms) && data.rooms.length > 0 && data.rooms.length <= MAX_ROOMS, 'Invalid room list');
  requireValue(Array.isArray(data.marks) && data.marks.length <= 128, 'Invalid mark list');
  for (const mark of data.marks) requireValue(typeof mark === 'string' && mark.length <= 100000 && /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(mark), 'Invalid mark image');
  const maze = new Maze();
  data.rooms.forEach((source, index) => {
    const cell = vector(source?.cell, 3, 100000);
    requireValue(cell.every(Number.isInteger), 'Room coordinates must be integers');
    if (index === 0) requireValue(same(cell, [0, 0, 0]), 'The starting room must be at the origin');
    if (index > 0) requireValue(!maze.cells.has(cell.join(',')), 'Duplicate room');
    const room = maze.room(cell);
    requireValue(Array.isArray(source.markers) && source.markers.length === 6 && source.markers.every(slot => Number.isInteger(slot) && slot >= -1 && slot < data.marks.length), 'Invalid face marks');
    room.markers = [...source.markers];
  });
  const roomId = value => Number.isInteger(value) && value >= 0 && value < maze.rooms.length;
  const endpoint = value => Array.isArray(value) && value.length === 2 && roomId(value[0]) && Number.isInteger(value[1]) && value[1] >= 0 && value[1] < 6;
  requireValue(Array.isArray(data.passages) && data.passages.length <= MAX_ROOMS * 3, 'Invalid passages');
  const boundaryKinds = new Map();
  for (const passage of data.passages) {
    requireValue(endpoint(passage?.a) && endpoint(passage?.b), 'Invalid passage endpoint');
    const [a, af] = passage.a, [b, bf] = passage.b;
    const kind = passage.kind;
    requireValue(['straight', 'up', 'down'].includes(kind) && a !== b, 'Invalid passage type');
    requireValue(!maze.rooms[a].links[af] && !maze.rooms[b].links[bf], 'Two passages occupy the same face');
    const sourceNormal = normals[af], direction = mul(normals[bf], -1);
    requireValue(kind === 'straight' ? same(sourceNormal, direction) : dot(sourceNormal, direction) === 0, 'Invalid passage rotation');
    const aCell = maze.rooms[a].cell, bCell = maze.rooms[b].cell;
    requireValue(same(add(aCell, direction), bCell) || same(add(bCell, mul(sourceNormal, -1)), aCell), 'Passage does not match the cubic grid');
    const keys = [...new Set([maze.wallKey(a, af), maze.wallKey(b, bf)])];
    for (const key of keys) {
      const previous = boundaryKinds.get(key);
      requireValue(!previous || (previous !== 'straight' && kind !== 'straight'), 'Straight and folded passages conflict');
      boundaryKinds.set(key, kind);
      maze.walls.set(key, (maze.walls.get(key) || 0) + 1);
    }
    const q = rotationBetween(sourceNormal, direction), id = maze.nextLink++;
    maze.rooms[a].links[af] = {id, target: b, face: bf, q, kind, keys};
    maze.rooms[b].links[bf] = {id, target: a, face: af, q: inverse(q), kind, keys};
  }
  const validVector = (value, limit) => Array.isArray(value)&&value.length===3&&value.every(Number.isFinite)&&Math.hypot(...value)<=limit;
  const actor = (source, recover = false) => {
    requireValue(source && roomId(source.room), 'An object references a missing room');
    const up = unit(source.up);
    requireValue(normals.some(n => same(n, up)), 'Gravity must align with a room axis');
    const validPosition=Array.isArray(source.p)&&source.p.length===3&&source.p.every(v=>Number.isFinite(v)&&Math.abs(v)<=3.6);
    const p=recover&&!validPosition?mul(up,-(HALF-.5-.01)):vector(source.p,3,3.6);
    const velocity=recover&&(!validPosition||!validVector(source.velocity,BALL_MAX_SPEED))?[0,0,0]:vector(source.velocity,3,BALL_MAX_SPEED);
    return {room:source.room,p,up,velocity};
  };
  const player = {...actor(data.player), forward: unit(data.player.forward), pitch: data.player.pitch};
  requireValue(Math.abs(dot(player.up, player.forward)) < 1e-5 && Number.isFinite(player.pitch) && Math.abs(player.pitch) <= 89 * Math.PI / 180 + 1e-6, 'Invalid player view');
  requireValue(data.player.mode===undefined||['walk','ball'].includes(data.player.mode),'Invalid player mode');
  if(data.player.mode==='walk')player.mode='walk';
  if(data.player.mode==='ball'){
    Object.assign(player,{mode:'ball',controlled:true,radius:data.player.radius,
      omega:validVector(data.player.omega,BALL_MAX_SPIN)?[...data.player.omega]:[0,0,0],
      motorAxis:unit(data.player.motorAxis),spin:vector(data.player.spin,4),
      cameraForward:unit(data.player.cameraForward),cameraUp:unit(data.player.cameraUp)});
    requireValue(player.radius===.5&&Math.abs(Math.hypot(...player.spin)-1)<1e-5&&Math.abs(dot(player.cameraForward,player.cameraUp))<1e-5,'Invalid ball player');
  }
  requireValue(Array.isArray(data.balls) && data.balls.length <= 16, 'Up to 16 balls are allowed');
  const balls = data.balls.map(source => {
    const ball = {...actor(source,true), radius: source.radius, omega: validVector(source.omega,BALL_MAX_SPIN)?[...source.omega]:[0,0,0], motorAxis: unit(source.motorAxis), spin: vector(source.spin, 4)};
    requireValue(ball.radius === .5 && Math.abs(Math.hypot(...ball.spin) - 1) < 1e-5, 'Invalid ball');
    return ball;
  });
  return {maze, player, balls, marks: [...data.marks]};
}
