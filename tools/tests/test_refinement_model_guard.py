"""An observed interrupted GPU setup must fail before loading large weights."""
from pathlib import Path
import tempfile
import unittest

from tools.asset_refinement.model_benchmark import main


class InterruptedModelGuardTests(unittest.TestCase):
    def test_quarantined_vulkan_fails_before_weight_reads_or_launch(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary)
            (cache / "vulkan_interruption_receipt.json").write_text('{}')
            output = cache / "never_started"
            with self.assertRaisesRegex(RuntimeError, "GPU retries are disabled"):
                main(["--cache", str(cache), "--output", str(output),
                      "--backend", "vulkan", "--prompt-file", str(cache / "missing.txt")])
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
