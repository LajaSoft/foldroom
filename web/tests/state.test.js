import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Maze, createBall, movePlayer} from '../dist/core.js';
import {exportState, importState, initialPlayer} from '../dist/state.js';

function fixture() {
  const maze = new Maze();
  maze.create(0, 0, 'up', [0, 1, 0]);
  const side = maze.room([1, 0, 0]);
  maze.create(side.id, 1, 'down', [0, 1, 0]);
  maze.create(0, 4, 'straight', [0, 1, 0]);
  maze.rooms[0].markers[5] = 0;
  return {maze, player: initialPlayer(), balls: [createBall(.7)], marks: ['data:image/png;base64,aGVsbG8=']};
}
const save = f => exportState(f.maze, f.player, f.balls, f.marks);

test('JSON roundtrip preserves rooms, marks, actor state and inverse portal transport', () => {
  const original = fixture(), restored = importState(save(original));
  assert.deepEqual(JSON.parse(save(restored)), JSON.parse(save(original)));
  for (const room of original.maze.rooms) {
    room.links.forEach((link, face) => {
      if (!link) return;
      assert.deepEqual(restored.maze.transport(room.id, face, [1, -2, 1], [[0, 1, 0]]), original.maze.transport(room.id, face, [1, -2, 1], [[0, 1, 0]]));
    });
  }
  assert.deepEqual(restored.maze.walls, original.maze.walls);
  assert.throws(() => restored.maze.create(2, 1, 'straight', [0, 1, 0]), /already|only/);
  assert.throws(() => restored.maze.remove(0, 0), /one side/);
  assert.deepEqual(JSON.parse(save(restored)), JSON.parse(save(original)));
  restored.maze.remove(0, 4);
  assert.equal(restored.maze.rooms[4].links[5], null);
});

test('export preserves a folded loop whose lower-index endpoint is the reverse', () => {
  const maze = new Maze();
  const above = maze.create(0, 4, 'up', [0, 1, 0]).target;
  // Created from room 1 back into room 0; export visits its inverse first.
  maze.create(above, 0, 'down', [0, 1, 0]);
  const saved = exportState(maze, initialPlayer(), [], []);
  assert.equal(importState(saved).maze.passages, maze.passages);
});

test('invalid JSON and occupied portal endpoints are rejected without changing existing state', () => {
  const original = fixture(), before = save(original);
  assert.throws(() => importState('{'), /JSON/);
  const data = JSON.parse(before);
  data.passages.push(data.passages[0]);
  assert.throws(() => importState(JSON.stringify(data)), /Two passages/);
  assert.equal(save(original), before);
});

test('five-times walking speed preserves floor collision and portal crossing', () => {
  const maze = new Maze();
  const ordinary = initialPlayer(), fast = initialPlayer();
  movePlayer(maze, ordinary, .01, 1, 0);
  movePlayer(maze, fast, .01, 1, 0, 5);
  assert.ok(Math.abs((1.1 - fast.p[2]) / (1.1 - ordinary.p[2]) - 5) < 1e-8);
  assert.equal(fast.p[1], -2);
  maze.create(0, 5, 'up', [0, 1, 0]);
  for (let i = 0; i < 40; i++) movePlayer(maze, fast, .01, 1, 0, 5);
  assert.equal(fast.room, 1);
});


test('pruned player component exports and imports with a new origin', () => {
  const maze = new Maze();
  for (let index = 0; index < 4; index++) maze.create(index, 0, 'straight', [0, 1, 0]);
  const player = {...initialPlayer(), room: 4};
  maze.remove(1, 0);
  maze.prune(player.room, [player]);
  const saved = exportState(maze, player, [], []);
  const restored = importState(saved);
  assert.deepEqual(JSON.parse(exportState(restored.maze, restored.player, restored.balls, restored.marks)), JSON.parse(saved));
  assert.equal(restored.player.room, 2);
  assert.deepEqual(restored.maze.rooms[0].cell, [0, 0, 0]);
});


test('JSON exports use indented lines and bundled example imports', () => {
  const exported = save(fixture());
  assert.ok(exported.includes('\n  "rooms": ['));
  assert.ok(Math.max(...exported.split('\n').map(line => line.length)) < 4096);
  const web = readFileSync(new URL('../dist/example.json', import.meta.url), 'utf8');
  const restored = importState(web);
  assert.equal(restored.maze.rooms.length, 24);
  assert.equal(restored.maze.passages, 27);
});
