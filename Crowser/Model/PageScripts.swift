import Foundation

/// JavaScript that Crowser puts into pages. Kept in one place so each piece is easy to read and audit.
enum PageScripts {
    /// Game mode: no text selection, no long-press callout, no tap highlights, no double-tap or pinch zoom.
    static let game = #"""
    (function () {
      if (window.__crowserGame) return;
      window.__crowserGame = true;
      var css = '*:not(input):not(textarea):not([contenteditable]){-webkit-user-select:none!important;user-select:none!important;-webkit-touch-callout:none!important}'
        + '*{-webkit-tap-highlight-color:transparent!important}'
        + 'html,body{touch-action:manipulation;overscroll-behavior:none!important}';
      var style = document.createElement('style');
      style.id = 'crowser-game';
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
      var meta = document.querySelector('meta[name=viewport]');
      if (meta) {
        var content = meta.getAttribute('content') || '';
        if (content.indexOf('user-scalable') < 0) meta.setAttribute('content', content + ',maximum-scale=1,user-scalable=no');
      }
      document.addEventListener('contextmenu', function (e) { e.preventDefault(); }, { capture: true });
      document.addEventListener('selectstart', function (e) {
        var t = e.target;
        var editable = t && (t.isContentEditable || /^(INPUT|TEXTAREA)$/.test(t.tagName || ''));
        if (!editable) e.preventDefault();
      }, { capture: true });
    })();
    """#

    /// Fingerprint blocking: flattens the device details trackers combine into an ID,
    /// and adds invisible noise to canvas reads so canvas fingerprints don't match across sites.
    static let fingerprint = #"""
    (function () {
      if (window.__crowserFP) return;
      window.__crowserFP = true;
      function def(o, p, v) { try { Object.defineProperty(o, p, { get: function () { return v; }, configurable: true }); } catch (e) {} }
      try {
        def(Navigator.prototype, 'hardwareConcurrency', 4);
        def(Navigator.prototype, 'deviceMemory', 8);
        def(Navigator.prototype, 'plugins', []);
        def(Navigator.prototype, 'mimeTypes', []);
        if ('getBattery' in navigator) def(Navigator.prototype, 'getBattery', undefined);
        def(Screen.prototype, 'colorDepth', 24);
        def(Screen.prototype, 'pixelDepth', 24);
        var seed = Math.floor(Math.random() * 255);
        function noise(canvas) {
          try {
            if (!canvas.width || !canvas.height) return;
            var ctx = canvas.__crowser2d || null;
            if (!ctx) return;
            var w = Math.min(canvas.width, 8), h = Math.min(canvas.height, 8);
            var data = ctx.getImageData(0, 0, w, h);
            for (var i = 0; i < data.data.length; i += 4) data.data[i] = data.data[i] ^ ((seed >> (i % 7)) & 1);
            ctx.putImageData(data, 0, 0);
          } catch (e) {}
        }
        var getContext = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function (type) {
          var ctx = getContext.apply(this, arguments);
          if (type === '2d' && ctx) this.__crowser2d = ctx;
          return ctx;
        };
        var toDataURL = HTMLCanvasElement.prototype.toDataURL;
        HTMLCanvasElement.prototype.toDataURL = function () { noise(this); return toDataURL.apply(this, arguments); };
        var toBlob = HTMLCanvasElement.prototype.toBlob;
        HTMLCanvasElement.prototype.toBlob = function () { noise(this); return toBlob.apply(this, arguments); };
        var getImageData = CanvasRenderingContext2D.prototype.getImageData;
        CanvasRenderingContext2D.prototype.getImageData = function () {
          var data = getImageData.apply(this, arguments);
          if (data && data.data && data.data.length > 64) data.data[0] = data.data[0] ^ (seed & 1);
          return data;
        };
        function maskGL(proto) {
          if (!proto) return;
          var getParameter = proto.getParameter;
          proto.getParameter = function (p) {
            if (p === 37445) return 'Apple Inc.';
            if (p === 37446) return 'Apple GPU';
            return getParameter.call(this, p);
          };
        }
        maskGL(window.WebGLRenderingContext && WebGLRenderingContext.prototype);
        maskGL(window.WebGL2RenderingContext && WebGL2RenderingContext.prototype);
      } catch (e) {}
    })();
    """#

    /// Tells pages not to send where you came from to the next site.
    static let noReferrer = #"""
    (function () {
      var meta = document.createElement('meta');
      meta.name = 'referrer';
      meta.content = 'no-referrer';
      (document.head || document.documentElement).appendChild(meta);
    })();
    """#

    /// Dark pages: flips light pages dark, leaves pages that are already dark alone, and keeps photos and video natural.
    static let darkPage = #"""
    (function () {
      if (document.getElementById('crowser-dark')) return;
      function luminance(color) {
        var m = (color || '').match(/\d+(\.\d+)?/g);
        if (!m || m.length < 3) return 1;
        if (m.length > 3 && parseFloat(m[3]) === 0) return -1;
        return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255;
      }
      var body = document.body ? luminance(getComputedStyle(document.body).backgroundColor) : -1;
      var html = luminance(getComputedStyle(document.documentElement).backgroundColor);
      var ground = body >= 0 ? body : (html >= 0 ? html : 1);
      if (ground < 0.4) return;
      var style = document.createElement('style');
      style.id = 'crowser-dark';
      style.textContent = 'html{filter:invert(0.9) hue-rotate(180deg)!important;background:#fff!important}'
        + 'img,video,picture,canvas,iframe,embed,object,svg image,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important}';
      (document.head || document.documentElement).appendChild(style);
    })();
    """#

    /// Wraps your own CSS for a site in a style tag.
    static func userCSS(_ css: String) -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        return """
        (function () {
          var s = document.getElementById('crowser-user-css') || document.createElement('style');
          s.id = 'crowser-user-css';
          s.textContent = `\(escaped)`;
          (document.head || document.documentElement).appendChild(s);
        })();
        """
    }

    /// Runs your own JavaScript for a site, without letting a mistake break the page.
    static func userJS(_ js: String) -> String {
        "(function () { try {\n\(js)\n} catch (e) { console.error('Crowser site script:', e); } })();"
    }

    /// Reader view: pulls the article out of the page and re-sets it in Crowser's own type.
    static func reader(accent: String) -> String {
        """
        (function () {
          if (window.__crowserReader) return 'already';
          var best = null, score = 0;
          document.querySelectorAll('article, main, [role=main], [itemprop=articleBody], section, div').forEach(function (el) {
            var total = 0;
            el.querySelectorAll(':scope > p, :scope > div > p, :scope > section > p').forEach(function (p) { total += (p.innerText || '').length; });
            if (el.tagName === 'ARTICLE') total *= 1.3;
            if (total > score) { score = total; best = el; }
          });
          if (!best || score < 350) return 'none';
          var h1 = document.querySelector('h1');
          var title = (h1 && h1.innerText.trim()) || document.title;
          var clone = best.cloneNode(true);
          clone.querySelectorAll('script,style,noscript,iframe,form,button,nav,aside,footer,input,select,textarea,[aria-hidden=true],[class*=share],[class*=related],[class*=promo],[class*=newsletter],[class*=advert],[id*=ad-],[class*=ad-]').forEach(function (n) { n.remove(); });
          clone.querySelectorAll('h1').forEach(function (n) { if (n.innerText.trim() === title) n.remove(); });
          clone.querySelectorAll('[style]').forEach(function (n) { n.removeAttribute('style'); });
          clone.querySelectorAll('img[data-src]').forEach(function (n) { n.src = n.getAttribute('data-src'); });
          var words = (clone.innerText || '').split(/\\s+/).length;
          window.__crowserReader = true;
          document.querySelectorAll('link[rel=stylesheet], style').forEach(function (n) { n.remove(); });
          var style = document.createElement('style');
          style.textContent = 'html{-webkit-text-size-adjust:100%}body{margin:0;background:#F4F0E8;color:#1A1916;font:19px/1.65 ui-serif,"New York",Georgia,serif}'
            + '#crowser-reader{max-width:680px;margin:0 auto;padding:34px 22px 90px}'
            + '#crowser-reader h1.t{font-size:31px;line-height:1.18;margin:0 0 10px;font-weight:700}'
            + '#crowser-reader .src{font:600 13px ui-rounded,system-ui,sans-serif;color:#7F796E;margin-bottom:30px;letter-spacing:.02em;text-transform:uppercase}'
            + '#crowser-reader .src b{color:\(accent)}'
            + '#crowser-reader img,#crowser-reader video,#crowser-reader figure{max-width:100%;height:auto;border-radius:10px}'
            + '#crowser-reader figure{margin:24px 0}#crowser-reader figcaption{font:14px/1.4 ui-rounded,system-ui;color:#7F796E;margin-top:6px}'
            + '#crowser-reader a{color:inherit;text-decoration-color:\(accent);text-underline-offset:3px}'
            + '#crowser-reader blockquote{margin:22px 0;padding-left:18px;border-left:3px solid \(accent);font-style:italic}'
            + '#crowser-reader pre,#crowser-reader code{font-size:15px;white-space:pre-wrap;word-break:break-word}'
            + '@media(prefers-color-scheme:dark){body{background:#100F0E;color:#F1EDE5}#crowser-reader .src,#crowser-reader figcaption{color:#8F897E}}';
          document.head.appendChild(style);
          var vp = document.querySelector('meta[name=viewport]') || document.createElement('meta');
          vp.name = 'viewport';
          vp.content = 'width=device-width,initial-scale=1';
          document.head.appendChild(vp);
          var main = document.createElement('main');
          main.id = 'crowser-reader';
          var t = document.createElement('h1'); t.className = 't'; t.textContent = title;
          var src = document.createElement('div'); src.className = 'src';
          src.innerHTML = '<b>●</b> ' + location.hostname.replace(/^www\\./, '') + ' · ' + Math.max(1, Math.round(words / 230)) + ' min read';
          main.appendChild(t); main.appendChild(src); main.appendChild(clone);
          document.body.innerHTML = '';
          document.body.removeAttribute('class');
          document.body.removeAttribute('style');
          document.body.appendChild(main);
          window.scrollTo(0, 0);
          return 'ok';
        })();
        """
    }

    /// The page's readable text, for read aloud.
    static let readableText = #"""
    (function () {
      var el = document.getElementById('crowser-reader') || document.querySelector('article') || document.querySelector('main') || document.body;
      return (el.innerText || '').slice(0, 40000);
    })();
    """#

    /// Hide-element mode: the next tap hides what it lands on and reports a CSS selector for it.
    static let zapper = #"""
    (function () {
      if (window.__crowserZap) return;
      window.__crowserZap = true;
      var lit = null;
      var style = document.createElement('style');
      style.id = 'crowser-zap-style';
      style.textContent = '.crowser-zap-lit{outline:3px solid #E2531F!important;outline-offset:-3px!important;background-color:rgba(226,83,31,.15)!important;cursor:crosshair!important}';
      document.documentElement.appendChild(style);
      function selector(el) {
        var parts = [];
        while (el && el.nodeType === 1 && el !== document.body && el !== document.documentElement) {
          var s = el.tagName.toLowerCase();
          if (el.id && /^[A-Za-z][\w-]*$/.test(el.id)) { parts.unshift(s + '#' + el.id); return parts.join(' > '); }
          var i = 1, sib = el;
          while ((sib = sib.previousElementSibling)) { if (sib.tagName === el.tagName) i++; }
          parts.unshift(s + ':nth-of-type(' + i + ')');
          el = el.parentElement;
        }
        return 'body > ' + parts.join(' > ');
      }
      function light(e) {
        if (lit) lit.classList.remove('crowser-zap-lit');
        lit = e.target;
        if (lit && lit.classList) lit.classList.add('crowser-zap-lit');
      }
      function done() {
        window.__crowserZap = false;
        if (lit) lit.classList.remove('crowser-zap-lit');
        document.removeEventListener('touchstart', light, true);
        document.removeEventListener('mouseover', light, true);
        document.removeEventListener('click', pick, true);
        style.remove();
      }
      function pick(e) {
        e.preventDefault();
        e.stopPropagation();
        var el = e.target;
        if (!el || el === document.body || el === document.documentElement) { done(); return; }
        var sel = selector(el);
        el.style.setProperty('display', 'none', 'important');
        done();
        try { window.webkit.messageHandlers.crowserZap.postMessage(sel); } catch (err) {}
      }
      document.addEventListener('touchstart', light, true);
      document.addEventListener('mouseover', light, true);
      document.addEventListener('click', pick, true);
    })();
    """#

    /// Picture in picture for the biggest video on the page (or back to inline if it's already floating).
    static let pictureInPicture = #"""
    (function () {
      var videos = Array.prototype.slice.call(document.querySelectorAll('video'));
      if (!videos.length) return 'none';
      videos.sort(function (a, b) { return (b.videoWidth * b.videoHeight) - (a.videoWidth * a.videoHeight); });
      var v = videos.find(function (x) { return !x.paused; }) || videos[0];
      try {
        if (v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')) {
          v.webkitSetPresentationMode(v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
          return 'ok';
        }
        if (document.pictureInPictureEnabled) {
          if (document.pictureInPictureElement) document.exitPictureInPicture(); else v.requestPictureInPicture();
          return 'ok';
        }
      } catch (e) { return 'error'; }
      return 'unsupported';
    })();
    """#

    static let selectedText = "(window.getSelection ? window.getSelection().toString() : '').trim().slice(0, 120)"

    /// Game mode frame counter: a small readout in the top-left corner that never takes touches.
    static let fps = #"""
    (function () {
      if (window.__crowserFPS) return;
      window.__crowserFPS = true;
      var d = document.createElement('div');
      d.id = 'crowser-fps';
      d.style.cssText = 'position:fixed;top:8px;left:8px;z-index:2147483647;font:700 12px ui-monospace,Menlo,monospace;'
        + 'color:#F3EFE7;background:rgba(23,22,20,.78);padding:4px 8px 4px 7px;border-radius:8px;'
        + 'border-left:3px solid #E2531F;pointer-events:none;letter-spacing:.02em;font-variant-numeric:tabular-nums';
      d.textContent = '-- FPS';
      var frames = 0, last = performance.now(), low = 999;
      function tick(now) {
        frames++;
        if (now - last >= 500) {
          var fps = Math.round(frames * 1000 / (now - last));
          low = Math.min(low, fps);
          d.textContent = fps + ' FPS  ·  low ' + low;
          d.style.borderLeftColor = fps >= 55 ? '#5E8C3A' : (fps >= 30 ? '#C9932B' : '#E2531F');
          frames = 0; last = now;
        }
        requestAnimationFrame(tick);
      }
      function add() { (document.body || document.documentElement).appendChild(d); }
      if (document.body) add(); else document.addEventListener('DOMContentLoaded', add);
      setInterval(function () { low = 999; }, 10000);
      requestAnimationFrame(tick);
    })();
    """#

    static let stopZapper = #"""
    (function () {
      if (!window.__crowserZap) return;
      document.querySelectorAll('.crowser-zap-lit').forEach(function (n) { n.classList.remove('crowser-zap-lit'); });
      location.reload();
    })();
    """#
}
