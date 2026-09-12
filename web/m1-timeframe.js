(() => {
  function install() {
    const page = document.getElementById('bot-lab-page');
    const toolbar = page?.querySelector('.mt-toolbar');
    if (!page || !toolbar || toolbar.querySelector('[data-tf="M1"]')) return false;
    const first = toolbar.querySelector('[data-tf]');
    if (!first) return false;
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.tf = 'M1';
    button.textContent = '1m';
    first.insertAdjacentElement('beforebegin', button);
    return true;
  }
  function boot() {
    if (install()) return;
    setTimeout(boot, 150);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
