import hashlib
import importlib.util
from pathlib import Path
import tempfile
import shutil
from unittest.mock import patch
import unittest

SPEC = importlib.util.spec_from_file_location("package_model_asset", Path(__file__).resolve().parents[1] / "package_model_asset.py")
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)

class ModelStagingTests(unittest.TestCase):
    def test_reused_pack_id_packages_current_verified_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original_root = package.ROOT
            package.ROOT = root
            try:
                source = root / "source.bin"
                source.write_bytes(b"new verified model")
                manifest = {"assetPackID": "fixture", "fileSelectors": [{"fileSource": "Models/fixture.bin"}]}
                target = root / "build/asset-pack-sources/fixture/Models/fixture.bin"
                target.parent.mkdir(parents=True)
                target.write_bytes(b"old model")
                digest = hashlib.sha256(source.read_bytes()).hexdigest()
                def clone(command, **kwargs):
                    self.assertEqual(command[:2], ["cp", "-c"])
                    shutil.copy2(command[2], command[3])
                with patch.object(package.subprocess, "run", side_effect=clone) as copy:
                    package.staged_manifest(root / "pack.json", manifest, source, source.stat().st_size, digest)
                    self.assertEqual(target.read_bytes(), source.read_bytes())
                    # Reusing the verified stage avoids another filesystem clone.
                    package.staged_manifest(root / "pack.json", manifest, source, source.stat().st_size, digest)
                    self.assertEqual(copy.call_count, 1)
                self.assertEqual(target.read_bytes(), source.read_bytes())
            finally:
                package.ROOT = original_root
