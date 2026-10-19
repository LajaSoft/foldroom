import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {importState, exportState} from '../../web/dist/state.js';

const text = readFileSync(new URL('native-export.json', import.meta.url), 'utf8');
const state = importState(text);
assert.equal(state.player.mode, 'ball');
assert.ok(state.maze.rooms.length > 0);
assert.ok(Number.isFinite(Math.hypot(...state.player.velocity)));
const second = importState(exportState(state.maze,state.player,state.balls,state.marks));
assert.equal(second.maze.passages,state.maze.passages);
assert.deepEqual(second.marks,state.marks);
console.log(`Original web importer accepted native JSON: ${state.maze.rooms.length} rooms, ${state.maze.passages} passages, ${state.balls.length} balls, ${state.marks.length} PNG marks.`);
