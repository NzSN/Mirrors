import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location("junction_calibration", Path(__file__).with_name("junction_calibration.py"))
calibration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(calibration)


class JunctionCalibrationCases(unittest.TestCase):
    def test_matrix_covers_the_jp0_surface(self):
        self.assertEqual(set(calibration.CASES), {
            "mixed-and-or", "mixed-or-and", "mixed-long-chain", "and-chain", "or-chain",
            "paren-left-and-or", "paren-right-and-or", "paren-left-or-and",
            "paren-right-or-and", "symbolic-word-alias", "word-mixed-alias",
            "prefix-single", "prefix-and", "prefix-nested", "prefix-mixed-column", "prefix-inline-opposite",
        })

    def test_two_item_prefix_supplement_distinguishes_boundaries(self):
        self.assertEqual(set(calibration.PREFIX_SUPPLEMENT_CASES), {
            "prefix-two-item-mixed-column", "prefix-two-item-inline-opposite",
            "prefix-parenthesized-outdented", "prefix-switch-back",
        })


if __name__ == "__main__":
    unittest.main()
