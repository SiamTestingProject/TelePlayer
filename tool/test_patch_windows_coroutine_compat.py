import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("patch_windows_coroutine_compat.py")
SPEC = importlib.util.spec_from_file_location("patch_windows_coroutine_compat", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PatchWindowsCoroutineCompatTests(unittest.TestCase):
    def _write_fixture(self, directory: Path, text: str) -> Path:
        path = directory / "CMakeLists.txt"
        path.write_text(text, encoding="utf-8")
        return path

    def test_adds_msvc_definition_after_project(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = self._write_fixture(
                Path(temp_dir),
                "cmake_minimum_required(VERSION 3.14)\n"
                "project(runner LANGUAGES CXX)\n"
                "add_subdirectory(flutter)\n",
            )

            changed = MODULE.patch_cmake(path)
            text = path.read_text(encoding="utf-8")

            self.assertTrue(changed)
            self.assertIn("if(MSVC)", text)
            self.assertIn(MODULE.MARKER, text)
            self.assertLess(text.index(MODULE.MARKER), text.index("add_subdirectory(flutter)"))

    def test_patch_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = self._write_fixture(
                Path(temp_dir),
                "cmake_minimum_required(VERSION 3.14)\nproject(runner LANGUAGES CXX)\n",
            )

            self.assertTrue(MODULE.patch_cmake(path))
            first = path.read_text(encoding="utf-8")
            self.assertFalse(MODULE.patch_cmake(path))
            second = path.read_text(encoding="utf-8")

            self.assertEqual(first, second)
            self.assertEqual(second.count(MODULE.MARKER), 1)

    def test_missing_project_fails_without_modifying_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = self._write_fixture(Path(temp_dir), "cmake_minimum_required(VERSION 3.14)\n")
            before = path.read_text(encoding="utf-8")

            with self.assertRaises(RuntimeError):
                MODULE.patch_cmake(path)

            self.assertEqual(before, path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
