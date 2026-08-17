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


if __name__ == "__main__":
    unittest.main()
