// This runs after the guide markup and before the website's example scripts.
(function () {
  var context = window.guideContext || {};
  var topic = context.topicID || null;
  window.angroveSaved = context.savedTerms || [];
  var topics = Array.from(document.querySelectorAll('.guide-topic'));
  if (topic) {
    document.documentElement.dataset.guideTopic = topic;
    document.querySelector('.page-hero').remove();
    document.querySelector('.guide__toc').remove();
    topics.forEach(function (article) { if (article.id !== topic) article.remove(); });
  } else {
    document.querySelector('.guide__topics').remove();
    document.querySelectorAll('[data-guide-topic]').forEach(function (button) {
      button.addEventListener('click', function () {
        window.webkit.messageHandlers.guideTopic.postMessage(button.dataset.guideTopic);
      });
    });
  }

  var palette = {};
  function recolorIcons() {
    document.querySelectorAll('img').forEach(function (image) {
      var original = image.dataset.guideOriginalSrc || image.getAttribute('src') || '';
      if (!original.startsWith('data:image/svg+xml;base64,')) return;
      image.dataset.guideOriginalSrc = original;
      var svg = atob(original.split(',')[1]);
      svg = svg.replace(/#4a321c|#614c40|rgb\(74,\s*50,\s*28\)/gi, palette.brown || '#4A321C');
      svg = svg.replace(/#86803e/gi, palette['light-green'] || '#86803E');
      svg = svg.replace(/rgba\(74,\s*50,\s*28,\s*([\d.]+)\)/gi, function (_, alpha) {
        return 'rgba(' + palette['guide-ink-rgb'] + ',' + alpha + ')';
      });
      var themed = 'data:image/svg+xml;base64,' + btoa(svg);
      if (image.getAttribute('src') !== themed) image.src = themed;
    });
  }
  window.applyGuideAppearance = function (next, isDark) {
    palette = next;
    if (typeof isDark === 'boolean') context.isDark = isDark;
    Object.keys(palette).forEach(function (name) {
      document.documentElement.style.setProperty('--' + name, palette[name]);
    });
    document.documentElement.style.colorScheme = context.isDark ? 'dark' : 'light';
    recolorIcons();
    document.dispatchEvent(new CustomEvent('guide:appearance'));
  };
  new MutationObserver(recolorIcons).observe(document.body, { childList: true, subtree: true });

  window.restoreGuideSavedTerms = function (terms) {
    if (JSON.stringify(window.angroveSaved) === JSON.stringify(terms)) return;
    window.angroveSaved = terms;
    document.dispatchEvent(new CustomEvent('guide:restore-saved'));
    document.dispatchEvent(new CustomEvent('guide:saved', { detail: { restored: true } }));
  };
  document.addEventListener('guide:saved', function (event) {
    if (event.detail && event.detail.restored) return;
    window.webkit.messageHandlers.guideSaved.postMessage(window.angroveSaved || []);
  });
  if (context.palette) window.applyGuideAppearance(context.palette);
  document.documentElement.dataset.guideReady = 'true';
})();
