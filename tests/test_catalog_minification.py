import os
import sys
import json
import unittest
import pathlib

class TestCatalogMinification(unittest.TestCase):
    def setUp(self):
        self.root_dir = pathlib.Path(__file__).parents[1]
        self.plugin_dir = self.root_dir / "storefront.koplugin"

    def test_parse_release_dict_omits_body(self):
        sys.path.insert(0, str(self.root_dir / "tools"))
        try:
            import build_catalog
            dummy_release = {
                "tag_name": "v1.0.0",
                "name": "Version 1.0.0",
                "body": "This is a full changelog markdown that should be omitted.",
                "published_at": "2026-09-27T12:00:00Z",
                "prerelease": False,
                "assets": [
                    {
                        "name": "sample.koplugin.zip",
                        "browser_download_url": "https://example.com/sample.zip",
                        "size": 12345,
                    }
                ]
            }
            parsed = build_catalog.parse_release_dict(dummy_release)
            self.assertIsNotNone(parsed)
            self.assertEqual(parsed.get("tag_name"), "v1.0.0")
            self.assertNotIn("body", parsed, "body must be omitted from release dict to save bandwidth")
        finally:
            if str(self.root_dir / "tools") in sys.path:
                sys.path.remove(str(self.root_dir / "tools"))

    def test_catalog_json_minified(self):
        catalog_path = self.plugin_dir / "catalog.json"
        self.assertTrue(catalog_path.exists(), "catalog.json must exist")
        content = catalog_path.read_text(encoding="utf-8")
        # Ensure it parses cleanly
        data = json.loads(content)
        self.assertIn("plugins", data)
        # Ensure it is minified (no pretty-print indentation newlines on each field)
        lines = content.strip().splitlines()
        self.assertEqual(len(lines), 1, "catalog.json must be a single minified line without whitespace indentation")

    def test_storefront_net_catalog_etag_support(self):
        content = (self.plugin_dir / "storefront_net_catalog.lua").read_text(encoding="utf-8")
        self.assertIn("function CatalogClient.getStoredEtag()", content)
        self.assertIn("function CatalogClient.setStoredEtag(etag)", content)
        self.assertIn("function CatalogClient.clearStoredEtag()", content)
        self.assertIn('"If-None-Match"', content)
        self.assertIn("OK_NOT_MODIFIED", content)
        self.assertIn('"not_modified"', content)

    def test_main_lua_notification_and_refresh_support(self):
        content = (self.plugin_dir / "main.lua").read_text(encoding="utf-8")
        self.assertIn("function Storefront:scheduleNotificationTimer()", content)
        self.assertIn("function Storefront:onNetworkConnected()", content)
        self.assertIn('StorefrontToast.show(_("Catalog updated"), 2)', content)
        self.assertNotIn("self._session_bg_checks_done = nil", content)

    def test_screensaver_catalog_refresh_support(self):
        net_content = (self.plugin_dir / "storefront_net_catalog.lua").read_text(encoding="utf-8")
        self.assertIn("function CatalogClient.getStoredScreensaverEtag()", net_content)
        self.assertIn("function CatalogClient.setStoredScreensaverEtag(etag)", net_content)
        self.assertIn("function CatalogClient.clearStoredScreensaverEtag()", net_content)
        self.assertIn("function CatalogClient.fetchScreensaverCatalogToFile(dest_path)", net_content)
        self.assertIn("function CatalogClient.fetchScreensaverCatalog(url_to_fetch)", net_content)
        self.assertIn("staging_screensavers_file", net_content)
        self.assertIn("ok_swap_ss", net_content)

        ss_content = (self.plugin_dir / "storefront_screensavers_ui.lua").read_text(encoding="utf-8")
        self.assertIn("function StorefrontScreensavers.invalidateMemCache()", ss_content)
        self.assertIn("function StorefrontScreensavers.getLastFetched()", ss_content)

if __name__ == "__main__":
    unittest.main()
