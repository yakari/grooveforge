// Tests for the links from the in-app guide to the website guide.
//
// Each recipe in the help ends with "Watch the clip", which opens a section of
// the website guide. The two are edited separately and the French page uses
// its own section ids, so renaming a section on the site would break the link
// without anything noticing: the browser just opens the top of the page.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/widgets/user_guide_modal.dart';

/// Every `id="..."` attribute in the HTML file at [path].
Set<String> _idsIn(String path) {
  final html = File(path).readAsStringSync();
  return RegExp(r'id="([^"]+)"').allMatches(html).map((m) => m.group(1)!).toSet();
}

void main() {
  final englishIds = _idsIn('website/guide/index.html');
  final frenchIds = _idsIn('website/fr/guide/index.html');

  test('every clip link has a section on the English guide', () {
    for (final anchor in guideClipAnchors.keys) {
      expect(englishIds, contains(anchor), reason: 'guide/#$anchor');
    }
  });

  test('every clip link has a section on the French guide', () {
    for (final anchor in guideClipAnchors.values) {
      expect(frenchIds, contains(anchor), reason: 'fr/guide/#$anchor');
    }
  });
}
