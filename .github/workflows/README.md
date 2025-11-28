# GitHub Actions Workflows

This directory contains GitHub Actions workflows for building and testing FlowVision.

## Build Workflow

The `build.yml` workflow automatically builds FlowVision on:
- Push to `main`, `master`, or `issue-*` branches
- Pull requests to `main` or `master`
- Manual trigger via GitHub Actions UI

## Downloading Build Artifacts

### From GitHub Web Interface

1. **Navigate to Actions tab:**
   - Go to your repository on GitHub
   - Click on the **Actions** tab

2. **Find your workflow run:**
   - Click on the workflow run you want (e.g., "Build FlowVision")
   - You'll see all the jobs that ran

3. **Download the artifact:**
   - Scroll down to the **Artifacts** section at the bottom
   - Click on **FlowVision.app** to download
   - The artifact is a ZIP file containing the app

4. **Extract and test:**
   ```bash
   # Extract the downloaded ZIP
   unzip FlowVision.app.zip
   
   # Open the app (may need to remove quarantine first)
   xattr -rd com.apple.quarantine FlowVision.app
   open FlowVision.app
   ```

### From GitHub CLI

If you have `gh` CLI installed:

```bash
# List recent workflow runs
gh run list --workflow=build.yml

# Download artifacts from a specific run
gh run download <run-id> --name FlowVision.app

# Or download from the latest run
gh run download --name FlowVision.app
```

### Direct Download via API

You can also download artifacts programmatically:

```bash
# Get run ID from workflow runs
RUN_ID=$(gh run list --workflow=build.yml --limit 1 --json databaseId --jq '.[0].databaseId')

# Download artifact
gh run download $RUN_ID --name FlowVision.app
```

## Testing the Build

After downloading:

1. **Extract the ZIP file** (if needed)
2. **Remove quarantine attribute** (macOS security):
   ```bash
   xattr -rd com.apple.quarantine FlowVision.app
   ```
3. **Open the app:**
   ```bash
   open FlowVision.app
   ```
   Or double-click it in Finder

4. **Test your changes:**
   - The app will be the exact build from your branch
   - Test the scroll position fix (Issue #120)
   - Verify all functionality works as expected

## Artifact Retention

- Artifacts are retained for **7 days** (as configured in the workflow)
- After 7 days, they are automatically deleted
- Download important builds before they expire

## Troubleshooting

### "App is damaged" error on macOS
This is due to macOS Gatekeeper. Fix it:
```bash
xattr -rd com.apple.quarantine FlowVision.app
```

### Can't find artifacts
- Make sure the workflow run completed successfully (green checkmark)
- Check that the "Upload build artifact" step completed
- Artifacts are only available for completed runs

### Artifact expired
- Artifacts are deleted after 7 days
- Re-run the workflow to generate a new build
- Or download immediately after build completes

## Branch-Specific Builds

When you push to a branch (like `issue-120-scroll-position`):
- The workflow automatically runs
- Build artifacts are tagged with the branch name in the workflow run
- You can download and test your branch-specific build
- Perfect for testing PRs before merging

## Example Workflow

```bash
# 1. Push your branch
git push origin issue-120-scroll-position

# 2. Wait for build to complete (check Actions tab)

# 3. Download artifact
gh run download --name FlowVision.app

# 4. Extract and test
unzip FlowVision.app.zip
xattr -rd com.apple.quarantine FlowVision.app
open FlowVision.app

# 5. Test your changes!
```

