"""Preserve observed source precision through game texture conversion."""
import unittest

import numpy as np
from PIL import Image

from tools.asset_refinement.prepare_scans import decode8


class ScanConversionTests(unittest.TestCase):
    def test_16bit_roughness_retains_range_instead_of_clipping_white(self):
        image = Image.fromarray(np.array([[0, 16315, 32768, 54507, 65535]], dtype=np.uint16))
        result = decode8(image, "roughness")
        self.assertEqual(result.mode, "L")
        self.assertEqual(list(result.getdata()), [0, 63, 128, 212, 255])

    def test_rgb_normal_keeps_signed_vector_encoding(self):
        image = Image.new("RGB", (1, 1), (112, 140, 253))
        self.assertEqual(decode8(image, "normal").getpixel((0, 0)), (112, 140, 253))


if __name__ == "__main__":
    unittest.main()
