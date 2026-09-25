(function () {
  var root = document.documentElement;
  function pick() {
    var q = new URLSearchParams(location.search).get('lang');
    if (q === 'en' || q === 'vi') return q;
    try {
      var saved = localStorage.getItem('cbfh-lang');
      if (saved === 'en' || saved === 'vi') return saved;
    } catch (e) {}
    return (navigator.language || '').toLowerCase().indexOf('vi') === 0 ? 'vi' : 'en';
  }
  function apply(lang) {
    root.setAttribute('data-lang', lang);
    root.setAttribute('lang', lang);
    var buttons = document.querySelectorAll('[data-set-lang]');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].setAttribute('aria-pressed', String(buttons[i].getAttribute('data-set-lang') === lang));
    }
    var t = root.getAttribute('data-title-' + lang);
    if (t) document.title = t;
  }
  var initial = pick();
  apply(initial);
  document.addEventListener("DOMContentLoaded", function () { apply(root.getAttribute("data-lang") || initial); });
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-set-lang]');
    if (!b) return;
    var lang = b.getAttribute('data-set-lang');
    try { localStorage.setItem('cbfh-lang', lang); } catch (err) {}
    apply(lang);
  });
})();
