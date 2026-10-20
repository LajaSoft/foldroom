export function joystickAxes(dx, dy, radius = 46) {
  const distance = Math.hypot(dx, dy);
  if (distance < radius * .12) return {forward: 0, side: 0, x: dx, y: dy};
  const scale = Math.min(1, radius / distance);
  return {forward: -dy * scale / radius, side: dx * scale / radius, x: dx * scale, y: dy * scale};
}

export function attachTouchControls({canvas, isActive, onMove, onLook, onCarve, onZoom = () => {}}) {
  const stick = document.getElementById('joystick');
  const knob = document.getElementById('joystickKnob');
  let stickId = null, pinchDistance = null;
  const fingers = new Map();
  const distance = () => {const [a,b]=[...fingers.values()];return Math.hypot(a.x-b.x,a.y-b.y);};
  const reset = () => {
    stickId = null; fingers.clear(); pinchDistance = null;
    knob.style.transform = 'translate(0px, 0px)';
    onMove(0, 0);
  };
  const moveStick = event => {
    const rect = stick.getBoundingClientRect();
    const axes = joystickAxes(event.clientX - rect.left - rect.width / 2, event.clientY - rect.top - rect.height / 2);
    knob.style.transform = `translate(${axes.x}px, ${axes.y}px)`;
    onMove(axes.forward, axes.side);
  };
  stick.addEventListener('pointerdown', event => {
    if (!isActive() || stickId !== null) return;
    event.preventDefault();
    stickId = event.pointerId;
    stick.setPointerCapture(stickId);
    moveStick(event);
  });
  stick.addEventListener('pointermove', event => {
    if (event.pointerId === stickId && isActive()) moveStick(event);
  });
  const releaseStick = event => {
    if (event.pointerId !== stickId) return;
    stickId = null;
    knob.style.transform = 'translate(0px, 0px)';
    onMove(0, 0);
  };
  for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) stick.addEventListener(name, releaseStick);
  canvas.addEventListener('pointerdown', event => {
    if (!isActive() || event.pointerType === 'mouse' || fingers.size >= 2) return;
    event.preventDefault();
    fingers.set(event.pointerId,{x:event.clientX,y:event.clientY});
    canvas.setPointerCapture(event.pointerId);
    pinchDistance=fingers.size===2?distance():null;
  });
  canvas.addEventListener('pointermove', event => {
    const previous=fingers.get(event.pointerId);
    if (!previous || !isActive()) return;
    event.preventDefault();
    fingers.set(event.pointerId,{x:event.clientX,y:event.clientY});
    if(fingers.size===2){
      const next=distance();
      if(pinchDistance>4&&next>4)onZoom(Math.log(pinchDistance/next)/.002);
      pinchDistance=next;
      return;
    }
    onLook(event.clientX-previous.x,event.clientY-previous.y);
  });
  const releaseLook = event => {
    if(!fingers.delete(event.pointerId))return;
    pinchDistance=null;
  };
  for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) canvas.addEventListener(name, releaseLook);
  document.querySelectorAll('[data-carve]').forEach(button => {
    button.addEventListener('click', event => {
      event.stopPropagation();
      if (isActive()) onCarve(button.dataset.carve);
    });
  });
  window.addEventListener('blur', reset);
  document.addEventListener('visibilitychange', () => { if (document.hidden) reset(); });
  // Menu changes cancel held fingers, including a joystick captured under the overlay.
  new MutationObserver(() => { if (!isActive()) reset(); }).observe(document.body, {attributes: true, attributeFilter: ['class']});
}
