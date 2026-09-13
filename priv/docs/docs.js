function mountPreviews() {
  for (const element of document.querySelectorAll('.smith-doc-preview[data-preview]')) {
    if (element.querySelector('iframe')) continue;
    const frame = document.createElement('iframe');
    const url = new URL('./viewer.html', import.meta.url);
    url.searchParams.set('model', element.dataset.preview);
    frame.src = url.href;
    frame.title = `${element.dataset.label} — interactive 3D preview`;
    frame.loading = 'lazy';
    frame.allow = 'fullscreen';
    frame.style.cssText = 'display:block;width:100%;height:500px;border:0;margin:1rem 0;';
    element.replaceChildren(frame);
  }
}

mountPreviews();
window.addEventListener('exdoc:loaded', mountPreviews);
