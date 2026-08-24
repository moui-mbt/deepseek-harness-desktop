(function () {
  function syncRail() {
    var frame = document.querySelector('.pI_x6G_frame');
    var root = document.querySelector('.hHd-Xa_root');
    if (!frame || !root) return;
    if (root.classList.contains('hHd-Xa_collapsed')) {
      frame.setAttribute('data-moui-collapsed-rail-safe', 'true');
    } else {
      frame.removeAttribute('data-moui-collapsed-rail-safe');
    }
  }

  syncRail();
  if (window.MutationObserver && document.documentElement) {
    new MutationObserver(syncRail).observe(document.documentElement, {
      subtree: true,
      attributes: true,
      attributeFilter: ['class']
    });
  }
})();
