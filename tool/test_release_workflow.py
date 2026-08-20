from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseWorkflowTest(unittest.TestCase):
    def test_main_branch_publishes_stable_semantic_release(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn('elif [[ "$GITHUB_REF_NAME" == "main" ]]; then', workflow)
        self.assertIn('RELEASE_TAG="v$APP_VERSION"', workflow)
        self.assertIn('RELEASE_NAME="$APP_NAME v$APP_VERSION"', workflow)
        self.assertIn('RELEASE_PRERELEASE="false"', workflow)
        self.assertIn('prerelease: ${{ env.RELEASE_PRERELEASE }}', workflow)

    def test_main_branch_artifacts_use_semantic_version_names(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn('elif [[ "${GITHUB_REF_NAME}" == "main" ]]; then', workflow)
        self.assertIn('ARTIFACT_REF="v${APP_VERSION}"', workflow)
        self.assertIn("elseif ($rawRef -eq 'main')", workflow)
        self.assertIn('$artifactRef = "v$($mainVersionMatch.Groups[1].Value)"', workflow)

    def test_non_main_branch_can_remain_prerelease(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn('RELEASE_TAG="build-$GITHUB_RUN_NUMBER"', workflow)
        self.assertIn('RELEASE_PRERELEASE="true"', workflow)

    def test_android_builds_parallelize_expensive_release_outputs(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("  android_apks:\n", workflow)
        self.assertIn("  android_bundle:\n", workflow)
        self.assertIn("  android:\n", workflow)
        self.assertIn("needs: [android_apks, android_bundle]", workflow)
        self.assertIn("Build Android ABI APKs", workflow)
        self.assertIn("Build Android AAB + universal APK", workflow)

    def test_android_uses_gradle_build_cache(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertGreaterEqual(workflow.count("uses: gradle/actions/setup-gradle@v6"), 2)
        self.assertGreaterEqual(workflow.count("org.gradle.caching=true"), 2)
        self.assertGreaterEqual(workflow.count("org.gradle.parallel=true"), 2)

    def test_universal_apk_is_generated_from_aab_without_third_flutter_build(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn('BUNDLETOOL_VERSION: "1.18.3"', workflow)
        self.assertIn("bundletool-all-${BUNDLETOOL_VERSION}.jar", workflow)
        self.assertIn("--mode=universal", workflow)
        self.assertIn('unzip -p "$APKS" universal.apk', workflow)
        self.assertNotIn("- name: Build universal APK\n        run: flutter build apk", workflow)

    def test_android_validation_runs_in_parallel_with_builds(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("  quality:\n    name: Validate Flutter source", workflow)
        self.assertIn("needs: [quality, android, windows]", workflow)

    def test_release_publish_uses_node24_and_has_a_503_fallback(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        fallback = (ROOT / "tool/publish_github_release.sh").read_text(encoding="utf-8")
        self.assertIn("uses: softprops/action-gh-release@v3", workflow)
        self.assertNotIn("uses: softprops/action-gh-release@v2", workflow)
        self.assertIn("id: github_release", workflow)
        self.assertIn("continue-on-error: true", workflow)
        self.assertIn("if: steps.github_release.outcome == 'failure'", workflow)
        self.assertIn("run: bash tool/publish_github_release.sh", workflow)
        self.assertIn('RELEASE_MAX_ATTEMPTS:-4', fallback)
        self.assertIn('RELEASE_INITIAL_RETRY_DELAY:-5', fallback)
        self.assertIn('RELEASE_MAX_RETRY_DELAY:-20', fallback)
        self.assertIn('gh release view "$RELEASE_TAG"', fallback)
        self.assertIn('release create "$RELEASE_TAG"', fallback)
        self.assertIn('gh "${create_args[@]}"', fallback)
        self.assertIn('gh release upload "$RELEASE_TAG"', fallback)
        self.assertIn("--clobber", fallback)

    def test_windows_release_bundles_tdlib_runtime(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        bundler = (ROOT / "tool/bundle_windows_tdlib.ps1").read_text(encoding="utf-8")
        self.assertIn('TDLIB_NATIVE_VERSION: "1.8.21.2"', workflow)
        self.assertIn("- name: Bundle Windows TDLib runtime", workflow)
        self.assertIn("run: ./tool/bundle_windows_tdlib.ps1 -SkipIfPresent", workflow)
        self.assertIn("tdlib.native.win-x64", bundler)
        self.assertIn("Invoke-WebRequest", bundler)
        self.assertIn("TDJSON_WINDOWS_DLL_BASE64", bundler)
        self.assertIn("tdjson.dll", bundler)
        self.assertIn("Copy-VisualCRuntime", bundler)
        self.assertIn("vcruntime140.dll", bundler)
        self.assertIn("vcruntime140_1.dll", bundler)
        self.assertIn("msvcp140.dll", bundler)
        self.assertIn("Copy-Item", bundler)
        self.assertIn("SkipIfPresent", bundler)
        self.assertIn("Test-TdlibRuntimePresent", bundler)
        self.assertIn(".teleplayer-tdlib-version", bundler)



if __name__ == "__main__":
    unittest.main()
