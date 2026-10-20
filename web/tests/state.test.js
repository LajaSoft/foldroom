import test from 'node:test';
import assert from 'node:assert/strict';
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
  restored.maze.remove(0, 0);
  assert.equal(restored.maze.rooms[1].links[3], null);
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
