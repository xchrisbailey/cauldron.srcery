const root = document.documentElement;
const reduced = matchMedia('(prefers-reduced-motion: reduce)');

// Theme: follow the system until the visitor picks one.
const toggle = document.querySelector('.theme-toggle');
const isLight = () => root.dataset.theme
  ? root.dataset.theme === 'light'
  : matchMedia('(prefers-color-scheme: light)').matches;
const labelToggle = () => { toggle.textContent = isLight() ? 'Dark mode' : 'Light mode'; };
toggle.hidden = false;
labelToggle();
toggle.addEventListener('click', () => {
  root.dataset.theme = isLight() ? 'dark' : 'light';
  labelToggle();
});

// The boiling pot holds still for anyone who asked for less motion.
const video = document.querySelector('.hero__video');
if (reduced.matches) video.pause();

// Device tabs on the plate.
const tabs = [...document.querySelectorAll('[data-tab]')];
const show = (name) => {
  for (const tab of tabs) tab.setAttribute('aria-selected', String(tab.dataset.tab === name));
  for (const shot of document.querySelectorAll('[data-shot]')) shot.classList.toggle('is-on', shot.dataset.shot === name);
};
tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => show(tab.dataset.tab));
  tab.addEventListener('keydown', (event) => {
    const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
    if (!step) return;
    const next = tabs[(index + step + tabs.length) % tabs.length];
    next.focus();
    show(next.dataset.tab);
  });
});

// Servings: every quantity on the card scales from the recipe's four.
const FRACTIONS = [[0, ''], [0.125, '⅛'], [0.25, '¼'], [1 / 3, '⅓'], [0.5, '½'], [2 / 3, '⅔'], [0.75, '¾'], [1, '']];
const format = (value) => {
  let whole = Math.floor(value);
  let rest = value - whole;
  let best = FRACTIONS[0];
  for (const fraction of FRACTIONS) if (Math.abs(fraction[0] - rest) < Math.abs(best[0] - rest)) best = fraction;
  if (best[0] === 1) { whole += 1; best = FRACTIONS[0]; }
  if (whole === 0 && best[1] === '') return '⅛';
  return `${whole || ''}${best[1]}` || '0';
};
const BASE = 4;
const KCAL = 310;
let servings = BASE;
const lines = [...document.querySelectorAll('[data-ingredients] [data-q]')];
const servingsOut = document.querySelector('[data-servings]');
const kcalOut = document.querySelector('[data-kcal]');
const fewer = document.querySelector('[data-step="-1"]');
const render = () => {
  for (const line of lines) {
    const q = line.querySelector('.q');
    q.textContent = format(Number(line.dataset.q) * servings / BASE);
    q.classList.toggle('changed', servings !== BASE);
  }
  servingsOut.textContent = servings;
  kcalOut.textContent = (KCAL * servings).toLocaleString('en');
  fewer.disabled = servings === 1;
};
for (const button of document.querySelectorAll('[data-step]')) {
  button.addEventListener('click', () => {
    servings = Math.min(24, Math.max(1, servings + Number(button.dataset.step)));
    render();
  });
}

// Story: the step nearest the middle of the screen chooses the picture.
const steps = [...document.querySelectorAll('[data-step-index]')];
const pictures = [...document.querySelectorAll('[data-pic]')];
const choose = (index) => {
  steps.forEach((step, i) => step.classList.toggle('is-on', i === index));
  for (const picture of pictures) picture.classList.toggle('is-on', Number(picture.dataset.pic) === index);
};
choose(0);
if ('IntersectionObserver' in window) {
  const storyWatch = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) choose(steps.indexOf(entry.target));
  }, { rootMargin: '-45% 0px -45% 0px' });
  steps.forEach((step) => storyWatch.observe(step));
}

// Entrances: the parts of each section rise in order as it arrives.
const parts = document.querySelectorAll(
  '.plate__picture, .tabs, .plate h2, .plate__copy, .plate__actions, .sheet, .story__title, .slip h3, .slip p, .bill, .menu__plate, .kept h2, .kept__facts > div'
);
if (!reduced.matches) {
  const groups = new Map();
  for (const part of parts) {
    const section = part.closest('section, footer, li');
    const index = groups.get(section) ?? 0;
    groups.set(section, index + 1);
    part.style.setProperty('--i', index);
    part.classList.add('reveal');
  }
  // Anything that has reached the lower part of the screen, or been scrolled past, is shown.
  let pending = [...parts];
  let queued = false;
  const reveal = () => {
    queued = false;
    const line = innerHeight * 0.92;
    pending = pending.filter((part) => {
      if (part.getBoundingClientRect().top > line) return true;
      part.classList.add('in');
      return false;
    });
    if (!pending.length) removeEventListener('scroll', onScroll);
  };
  const onScroll = () => { if (!queued) { queued = true; requestAnimationFrame(reveal); } };
  addEventListener('scroll', onScroll, { passive: true });
  addEventListener('resize', onScroll);
  reveal();
}
