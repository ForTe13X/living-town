"""Prevent the copied-description failures seen in native review adapters."""
from pathlib import Path
import tempfile
import unittest

from tools.unreal.toolset_source import inspect_description, inspect_file


class ToolsetSourceTests(unittest.TestCase):
    def test_matching_closed_description_without_executing_module(self):
        source = ('raise RuntimeError("must never execute")\n'
                  'DESC = "owned seven-view review"\n'
                  '@unreal.uclass()\nclass ReviewTools:\n'
                  '    """owned seven-view review"""\n')
        report = inspect_description(source, "ReviewTools")
        self.assertFalse(report["module_executed"])
        self.assertFalse(report["native_registry_schema_verified"])

    def test_copied_cafe_description_refused(self):
        source = ('DESC = "material-resume views"\nclass CafeTools:\n'
                  '    """older reconstructed-entrance views"""\n')
        with self.assertRaisesRegex(ValueError, "description mismatch"):
            inspect_description(source, "CafeTools")

    def test_copied_avatar_description_refused(self):
        source = ('DESC = "surface diagnosis"\nclass AvatarTools:\n'
                  '    """saved avatar review"""\n')
        with self.assertRaisesRegex(ValueError, "description mismatch"):
            inspect_description(source, "AvatarTools")

    def test_missing_or_duplicate_class_refused(self):
        for classes in ["class Other: pass", 'class T: "x"\nclass T: "x"']:
            with self.assertRaisesRegex(ValueError, "Expected one top-level class"):
                inspect_description('DESC = "x"\n' + classes, "T")

    def test_dynamic_or_reassigned_description_refused(self):
        for declaration in ['DESC = make_description()',
                            'DESC = "x"\nDESC = "x"',
                            'DESC = "x"\nDESC += "y"']:
            with self.assertRaises(ValueError):
                inspect_description(declaration + '\nclass T: "x"', "T")

    def test_missing_empty_and_overridden_docstrings_refused(self):
        for source in ['DESC = "x"\nclass T: pass',
                       'DESC = ""\nclass T: ""',
                       'DESC = "x"\nclass T:\n    "x"\n    __doc__ = "y"']:
            with self.assertRaises(ValueError):
                inspect_description(source, "T")

    def test_clean_multiline_docstring_and_alternate_variable(self):
        report = inspect_description('DESCRIPTION: str = "first\\nsecond"\n'
                                     'class T:\n    """first\n    second"""',
                                     "T", "DESCRIPTION")
        self.assertEqual(report["description"], "first\nsecond")

    def test_bound_source_bytes_and_utf8_bom(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tools.py"
            data = b'\xef\xbb\xbfDESC = "x"\nclass T: "x"\n'
            path.write_bytes(data)
            report = inspect_file(path, "T")
            self.assertEqual(report["source"]["bytes"], len(data))
            self.assertEqual(len(report["source"]["sha256"]), 64)
            self.assertEqual(path.read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
