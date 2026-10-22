const toggle = document.querySelector('.theme-toggle');
const root = document.documentElement;

toggle.hidden = false;
toggle.addEventListener('click', () => {
  const light = root.dataset.theme !== 'light';
  root.dataset.theme = light ? 'light' : 'dark';
  toggle.textContent = light ? 'Dark mode' : 'Light mode';
  toggle.setAttribute('aria-pressed', String(light));
});

// Even if the disabled preview is changed in dev tools, don't send personal data.
document.querySelector('form').addEventListener('submit', (event) => {
  event.preventDefault();
});
