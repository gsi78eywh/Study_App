import 'dart:html' as html;

void launchWebUrl(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}
