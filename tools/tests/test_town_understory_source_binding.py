"""Regression for Python 3.12 preparation versus Blender Python 3.13 ASTs."""
import ast
import unittest
from tools.town_upgrade.understory import _ast_sha


class CanonicalSourceBinding(unittest.TestCase):
    def test_empty_fields_keep_original_recipe_identity(self):
        node=ast.parse('def source(x):\n    if x:\n        return 1\n').body[0]
        self.assertEqual(_ast_sha(node),'1f4f3a1f362354b8344f7fff3868d8c853a52f118244bbc492f8a8f800d87267')

    def test_real_recipe_mutation_changes_binding(self):
        first=ast.parse('def source(x):\n    if x:\n        return 1\n').body[0]
        changed=ast.parse('def source(x):\n    if x:\n        return 2\n').body[0]
        self.assertNotEqual(_ast_sha(first),_ast_sha(changed))


if __name__=='__main__':unittest.main()
