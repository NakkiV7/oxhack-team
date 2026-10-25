"""Static publication contracts; no network or provider calls."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.images = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'a':
            self.links.append(values.get('href', ''))
        if tag == 'img':
            self.images.append(values)
        if tag == 'script':
            self.scripts.append(values)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'index.html').read_text()
        self.page = Page()
        self.page.feed(self.source)

    def test_beta_actions_use_existing_invitation_and_explain_current_limits(self):
        self.assertEqual(self.page.links.count('https://testflight.apple.com/join/f3MhePbf'), 2)
        for text in ('0.1 (5)', 'iOS 26+', 'watchOS 26+', 'onboarding crash'):
            self.assertIn(text, self.source)

    def test_visitors_can_find_contributors_and_documented_demo(self):
        for section in ('/blob/main/docs/TEAM.md', '#what-the-demo-can-show'):
            self.assertIn('https://github.com/NakkiV7/oxhack-team' + section, self.page.links)

    def test_page_loads_only_local_real_captures_and_no_scripts(self):
        self.assertEqual(self.page.scripts, [])
        self.assertEqual(len(self.page.images), 2)
        for image in self.page.images:
            self.assertTrue(image['src'].startswith('assets/'))
            self.assertTrue((ROOT / image['src']).is_file())
            self.assertTrue(image['alt'])
            self.assertGreater(int(image['width']), 0)
            self.assertGreater(int(image['height']), 0)
        self.assertIn('iPhone and Watch simulator captures', self.source)


if __name__ == '__main__':
    unittest.main()
