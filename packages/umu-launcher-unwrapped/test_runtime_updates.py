import os
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

from urllib3.exceptions import HTTPError

from umu import umu_runtime


class RuntimeUpdatesTest(unittest.TestCase):
    runtime_ver = ("steamrt4", "steamrt4", "4183110")
    version = "4.0.20261007.263973"
    index_url = "https://repo.steampowered.com/steamrt4/images/latest-public-beta.txt"

    def setUp(self):
        self.temp = TemporaryDirectory(prefix="umu-runtime-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.local = self.root / "steamrt4"
        self.local.mkdir()
        (self.local / ".installed.ok").write_text("ok\n")
        (self.local / "VERSIONS.txt").write_text(
            f"#Name\tVersion\nsteamrt4\t{self.version}\tsteamrt4\t{self.version}\n"
        )
        (self.local / f"steamrt4_platform_{self.version}").mkdir()
        (self.local / "pressure-vessel").mkdir()
        self.http = MagicMock()
        self.pools = (MagicMock(), self.http)
        self.env = patch.dict(os.environ, {"UMU_RUNTIME_UPDATE": "1", "UMU_ZENITY": ""})
        self.env.start()
        self.addCleanup(self.env.stop)

    def setup_with_remote(self, version):
        self.http.request.return_value = SimpleNamespace(
            status=200, data=f"{version}\n".encode()
        )
        umu_runtime.setup_umu(self.local, self.runtime_ver, self.pools)
        self.http.request.assert_called_once_with("GET", self.index_url)

    def test_older_remote_does_not_download(self):
        with patch.object(umu_runtime, "_install_umu") as install:
            self.setup_with_remote("4.0.20260914.260627")
            install.assert_not_called()

    def test_same_remote_does_not_download(self):
        with patch.object(umu_runtime, "_install_umu") as install:
            self.setup_with_remote(self.version)
            install.assert_not_called()

    def test_newer_remote_downloads_selected_version(self):
        newer = "4.0.20261017.270000"
        with patch.object(umu_runtime, "_install_umu") as install:
            self.setup_with_remote(newer)
            install.assert_called_once_with(self.local, self.runtime_ver, newer, self.pools)

    def test_versions_are_compared_numerically(self):
        # A newer major version can sort before the local version as text.
        newer = "10.0.20261007.263973"
        with patch.object(umu_runtime, "_install_umu") as install:
            self.setup_with_remote(newer)
            install.assert_called_once_with(self.local, self.runtime_ver, newer, self.pools)

    def test_disabled_updates_reuse_runtime_without_network(self):
        with patch.dict(os.environ, {"UMU_RUNTIME_UPDATE": "0"}), patch.object(
            umu_runtime, "_install_umu"
        ) as install:
            umu_runtime.setup_umu(self.local, self.runtime_ver, self.pools)
            self.http.request.assert_not_called()
            install.assert_not_called()

    def test_first_install_still_downloads_when_updates_disabled(self):
        (self.local / ".installed.ok").unlink()
        with patch.dict(os.environ, {"UMU_RUNTIME_UPDATE": "0"}), patch.object(
            umu_runtime, "check_runtime", return_value=1
        ), patch.object(umu_runtime, "_install_umu") as install:
            self.setup_with_remote(self.version)
            install.assert_called_once_with(
                self.local, self.runtime_ver, self.version, self.pools
            )

    def test_download_metadata_and_archive_use_one_version(self):
        archive = "SteamLinuxRuntime_4.tar.xz"
        digest = MagicMock(status=200)
        digest.readline.side_effect = [f"{'0' * 64}  {archive}\n".encode()]
        self.http.request.side_effect = [
            digest,
            SimpleNamespace(status=200, data=f"{self.version}\n".encode()),
            SimpleNamespace(status=404),
        ]
        downloads = self.root / "downloads"
        downloads.mkdir()
        with patch.object(umu_runtime, "UMU_CACHE", self.root / "cache"), patch.object(
            umu_runtime, "get_tempdir", return_value=downloads
        ), self.assertRaises(HTTPError):
            umu_runtime._install_umu(
                self.local, self.runtime_ver, self.version, self.pools
            )
        urls = [call.args[1] for call in self.http.request.call_args_list]
        base_url = f"https://repo.steampowered.com/steamrt4/images/{self.version}"
        self.assertEqual(
            urls,
            [f"{base_url}/SHA256SUMS", f"{base_url}/BUILD_ID.txt", f"{base_url}/{archive}"],
        )


if __name__ == "__main__":
    unittest.main()
