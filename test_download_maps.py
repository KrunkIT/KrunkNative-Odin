import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import download_maps


class MapDownloadTests(unittest.TestCase):
    def test_official_ids_do_not_confuse_shipment_and_shipyard(self):
        self.assertEqual(len(download_maps.MAP_NAMES), 47)
        self.assertEqual(download_maps.MAP_NAMES[5], "Shipment")
        self.assertEqual(download_maps.MAP_NAMES[11], "Industry")
        self.assertEqual(download_maps.MAP_NAMES[30], "Shipyard")
        self.assertEqual(download_maps.map_filename(46), "candy_heist")

    def test_replace_and_repeat_without_duplicate_files(self):
        data = {"name": "Sandstorm", "objects": [{"p": [1, 2, 3]}], "spawns": [[0, 0, 0]]}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "sandstorm.json").write_text('{"old":true}', encoding="utf-8")
            target = output / "sandstorm_v3.json"
            target.write_text('{"old":true}', encoding="utf-8")
            with patch.object(download_maps, "fetch_json", return_value={"data": data}) as fetch:
                _, status = download_maps.update_map(2, output, "https://gapi.svc.krunker.io/maps")
                self.assertEqual(status, "replaced")
                self.assertEqual(json.loads(target.read_text()), data)
                self.assertFalse((output / "sandstorm.json").exists())
                modified = target.stat().st_mtime_ns
                self.assertEqual(download_maps.update_map(2, output, "https://gapi.svc.krunker.io/maps")[1], "unchanged")
                self.assertEqual(target.stat().st_mtime_ns, modified)
                fetch.assert_called_with("https://gapi.svc.krunker.io/maps/2")

    def test_bad_response_preserves_existing_map(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            target = output / "burg.json"
            target.write_bytes(b"existing valid map")
            with patch.object(download_maps, "fetch_json", return_value={"data": {"error": "unavailable"}}):
                with self.assertRaises(ValueError):
                    download_maps.update_map(0, output, "https://gapi.svc.krunker.io/maps")
            self.assertEqual(target.read_bytes(), b"existing valid map")


if __name__ == "__main__":
    unittest.main()
