// Pointer Lock is optional: embedded hosts may forbid it through iframe sandboxing.
export function attachPointerControls({canvas, document, window, isActive, setActive, onLook, onMode, onError}) {
  let mode = 'locked', pending = false, requestId = 0, drag = null;
  const locked = () => document.pointerLockElement === canvas;
  const resetDrag = () => {
    if (!drag) return;
    const id = drag.id;
    drag = null;
    if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
  };
  const useDrag = error => {
    if (!pending) return;
    pending = false;
    mode = 'drag';
    onError(error);
    onMode(mode);
    setActive(true);
  };
  const pause = () => {
    pending = false;
    requestId++;
    resetDrag();
    setActive(false);
    if (locked()) document.exitPointerLock();
  };
  document.addEventListener('pointerlockerror', () => {
    useDrag(new Error('The browser denied pointer lock.'));
  });
  document.addEventListener('pointerlockchange', () => {
    if (locked()) {
      if (!pending && !isActive()) {
        document.exitPointerLock();
        return;
      }
      pending = false;
      resetDrag();
      mode = 'locked';
      onMode(mode);
      setActive(true);
      return;
    }
    if (mode === 'locked') pause();
  });
  document.addEventListener('mousemove', event => {
    if (isActive() && locked()) onLook(event.movementX, event.movementY);
  });
  const isLookGesture = event => mode === 'drag' && (event.button === 1 || (event.button === 0 && Boolean(event.altKey)));
  canvas.addEventListener('pointerdown', event => {
    if (!isActive() || event.pointerType !== 'mouse' || !isLookGesture(event)) return;
    event.preventDefault();
    resetDrag();
    drag = {id: event.pointerId, x: event.clientX, y: event.clientY};
    canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener('pointermove', event => {
    if (!isActive() || !drag || drag.id !== event.pointerId) return;
    const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
    drag.x = event.clientX;
    drag.y = event.clientY;
    onLook(dx, dy);
  });
  for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    canvas.addEventListener(name, event => {
      if (drag?.id === event.pointerId) resetDrag();
    });
  }
  window.addEventListener('blur', pause);
  document.addEventListener('visibilitychange', () => {if (document.hidden) pause();});
  return {
    pause,
    isLookGesture,
    async enter() {
      if (pending || isActive()) return;
      canvas.focus({preventScroll: true});
      if (mode === 'drag') {
        setActive(true);
        return;
      }
      pending = true;
      const id = ++requestId;
      if (typeof canvas.requestPointerLock !== 'function') {
        useDrag(new Error('Pointer lock is unavailable in this browser.'));
        return;
      }
      try {
        await canvas.requestPointerLock();
      } catch (error) {
        if (id === requestId) useDrag(error);
      }
    }
  };
}
