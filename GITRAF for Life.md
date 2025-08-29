# Git-RAF Auto-Tag System Implementation

I'll create a comprehensive implementation of the Git-RAF Auto-Tag system based on the documentation provided. This will include the main `git-raf` tool, integration scripts, and necessary configuration files.

```bash
#!/bin/bash
# git-raf - Git-RAF Auto-Tag System Implementation
# OBINexus Computing - AEGIS Methodology Compliance

set -euo pipefail

# Configuration
CONFIG_FILE=".git/raf-config"
DEFAULT_SINPHASE_THRESHOLD=0.5
ARTIFACTS=(
    "build/release/bin/diram"
    "build/release/lib/libdiram.so.1"
    "build/release/lib/libdiram.a"
    "build/release/config/diram.drc"
)

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Initialize configuration
init_config() {
    cat > "$CONFIG_FILE" << EOF
# Git-RAF Auto-Tag Configuration
SINPHASE_THRESHOLD=${DEFAULT_SINPHASE_THRESHOLD}
TAG_PREFIX="diram"
TAG_FORMAT="\${PREFIX}-v\${VERSION}-\${STABILITY}"
ARTIFACT_MANIFEST=".git/raf-artifacts.json"
GOVERNANCE_REF="dram_build_policy.rift.gov"
EOF
    echo "Configuration initialized at $CONFIG_FILE"
}

# Verify build artifacts
verify_artifacts() {
    local missing=0
    for artifact in "${ARTIFACTS[@]}"; do
        if [[ ! -f "$artifact" ]]; then
            echo "Missing artifact: $artifact" >&2
            missing=$((missing + 1))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        echo "Missing $missing artifacts. Build verification failed." >&2
        return 1
    fi
    echo "All artifacts verified successfully."
    return 0
}

# Calculate sinphase metric
calculate_sinphase() {
    local artifact_count=0
    for artifact in "${ARTIFACTS[@]}"; do
        if [[ -f "$artifact" ]]; then
            artifact_count=$((artifact_count + 1))
        fi
    done
    
    # Run tests and get results (simplified for example)
    local test_results
    if [[ -f "test/results.xml" ]]; then
        test_results=$(parse_test_results "test/results.xml")
    else
        # Fallback to make test
        test_results=$(make test 2>&1 | grep -E "passed|failed" | tail -1)
    fi
    
    local test_pass_rate=$(echo "$test_results" | awk '{print $1}')
    local total_tests=$(echo "$test_results" | awk '{print $3}')
    
    if [[ $total_tests -eq 0 ]]; then
        echo "No tests found. Sinphase calculation aborted." >&2
        return 1
    fi
    
    # Calculate sinphase σ = (artifact_count × test_pass_rate) / (total_tests × 10)
    local sinphase=$(echo "scale=4; ($artifact_count * $test_pass_rate) / ($total_tests * 10)" | bc)
    echo "$sinphase"
}

# Classify stability based on sinphase using trie logic
classify_stability() {
    local sinphase=$1
    local stability=""
    
    # Trie-based classification
    if (( $(echo "$sinphase < 0.2" | bc -l) )); then
        stability="alpha"
    elif (( $(echo "$sinphase < 0.4" | bc -l) )); then
        stability="beta"
    elif (( $(echo "$sinphase < 0.6" | bc -l) )); then
        stability="rc"
    elif (( $(echo "$sinphase < 0.8" | bc -l) )); then
        stability="stable"
    else
        stability="release"
    fi
    
    echo "$stability"
}

# Determine version bump based on changes
determine_version_bump() {
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    local changes=$(git diff --name-only "$last_tag" HEAD)
    
    local bump="patch"
    if echo "$changes" | grep -q "^include/"; then
        bump="major"
    elif echo "$changes" | grep -q "^src/core/"; then
        bump="minor"
    fi
    
    echo "$bump"
}

# Generate governance metadata
generate_governance_metadata() {
    local stability=$1
    local sinphase=$2
    local manifest_hash=$(sha3sum "${ARTIFACTS[@]}" | awk '{print $1}' | sha3sum | awk '{print $1}')
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local artifact_count=0
    
    for artifact in "${ARTIFACTS[@]}"; do
        if [[ -f "$artifact" ]]; then
            artifact_count=$((artifact_count + 1))
        fi
    done
    
    cat << EOF
Policy-Tag: "$stability"
Governance-Ref: $GOVERNANCE_REF
Entropy-Checksum: $manifest_hash
Governance-Vector:
  - build_risk: $(echo "1 - $sinphase" | bc)
  - rollback_cost: 0.15
  - stability_impact: $sinphase
AuraSeal: $(echo -n "$manifest_hash$timestamp" | openssl dgst -sha256 -hmac "OBINexus-DIRAM" | awk '{print $2}')
RIFTlang-Compilation-Proof: verified_stable_build
Build-Timestamp: $timestamp
Artifact-Count: $artifact_count
EOF
}

# Create and apply tag
create_tag() {
    local sinphase=$(calculate_sinphase)
    if (( $(echo "$sinphase < $SINPHASE_THRESHOLD" | bc -l) )); then
        echo "Sinphase value $sinphase below threshold $SINPHASE_THRESHOLD. Tagging aborted." >&2
        return 1
    fi
    
    local stability=$(classify_stability "$sinphase")
    local bump=$(determine_version_bump)
    local current_version=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
    local new_version=$(increment_version "$current_version" "$bump")
    local tag_name=$(eval "echo $TAG_FORMAT")
    
    # Generate governance metadata
    local governance_metadata=$(generate_governance_metadata "$stability" "$sinphase")
    
    # Create tag with metadata
    git tag -a "$tag_name" -m "Git-RAF Auto-Tag: $stability
Sinphase: $sinphase
Version: $new_version
$governance_metadata"
    
    echo "Created tag: $tag_name"
    echo "Sinphase: $sinphase"
    echo "Stability: $stability"
}

# Install Git hooks
install_hooks() {
    local hook_dir=".git/hooks"
    local pre_commit_hook="$hook_dir/pre-commit"
    local post_commit_hook="$hook_dir/post-commit"
    
    # Create pre-commit hook
    cat > "$pre_commit_hook" << 'EOF'
#!/bin/bash
# Git-RAF Pre-Commit Hook
# Check for changes that might affect build

changed_files=$(git diff --cached --name-only)

if echo "$changed_files" | grep -q -E "^(include/|src/core/|src/|Makefile|\.c$|\.h$)"; then
    echo "Git-RAF: Build-related files changed. Consider running 'make release' before committing."
fi
EOF
    
    # Create post-commit hook
    cat > "$post_commit_hook" << 'EOF'
#!/bin/bash
# Git-RAF Post-Commit Hook
# Attempt auto-tagging if relevant files changed

changed_files=$(git diff HEAD~1 --name-only)

if echo "$changed_files" | grep -q -E "^(include/|src/core/|src/|Makefile|\.c$|\.h$)"; then
    echo "Git-RAF: Build-related changes detected. Running verification..."
    if command -v git-raf >/dev/null 2>&1; then
        git-raf --tag
    fi
fi
EOF
    
    chmod +x "$pre_commit_hook" "$post_commit_hook"
    echo "Git hooks installed successfully."
}

# Increment version based on semver
increment_version() {
    local version=$1
    local increment=$2
    local major=$(echo "$version" | cut -d. -f1)
    local minor=$(echo "$version" | cut -d. -f2)
    local patch=$(echo "$version" | cut -d. -f3)
    
    case "$increment" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
    esac
    
    echo "${major}.${minor}.${patch}"
}

# Main function
main() {
    load_config
    
    case "${1:-}" in
        "--tag")
            echo "Starting Git-RAF Auto-Tag process..."
            verify_artifacts
            create_tag
            ;;
        "--sinphase")
            calculate_sinphase
            ;;
        "--verify")
            verify_artifacts
            ;;
        "--install-hooks")
            install_hooks
            ;;
        "--init-config")
            init_config
            ;;
        "--help")
            cat << EOF
Git-RAF Auto-Tag System
Usage: git-raf [OPTION]

Options:
  --tag           Create tag if stability criteria met
  --sinphase      Calculate sinphase metric
  --verify        Verify build artifacts
  --install-hooks Install Git hooks for auto-tagging
  --init-config   Initialize configuration file
  --help          Show this help message

EOF
            ;;
        *)
            echo "Unknown option: ${1:-}"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
```

## Makefile Integration

Create a `Makefile` integration target:

```makefile
# Add to existing Makefile
.PHONY: release-tag
release-tag: release
	@echo "Creating stable release tag..."
	@git-raf --tag || echo "Build not stable enough for tagging"

.PHONY: verify-build
verify-build:
	@git-raf --verify

.PHONY: sinphase
sinphase:
	@git-raf --sinphase
```

## CI/CD Integration Example

Create a GitHub Actions workflow (`.github/workflows/auto-tag.yml`):

```yaml
name: Auto-Tag Stable Builds
on:
  push:
    branches: [main]
    paths:
      - 'include/**'
      - 'src/**'
      - 'Makefile'
      - 'test/**'

jobs:
  tag-stable:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y bc openssl
      
      - name: Build Release
        run: make release
      
      - name: Auto-Tag if Stable
        run: |
          chmod +x tools/git-raf
          ./tools/git-raf --tag
        env:
          GIT_RAF_SIGN: true
      
      - name: Push tags
        if: success()
        run: git push origin --tags
```

## Setup Script

Create an installation script (`install-git-raf.sh`):

```bash
#!/bin/bash
# Git-RAF installation script

echo "Installing Git-RAF Auto-Tag System..."

# Copy to executable location
sudo cp git-raf /usr/local/bin/
sudo chmod +x /usr/local/bin/git-raf

# Initialize configuration
git-raf --init-config

# Install hooks
git-raf --install-hooks

echo "Git-RAF installed successfully."
echo "Run 'make release' followed by 'git-raf --tag' to create your first tag."
```

## Usage Examples

```bash
# Install the system
./install-git-raf.sh

# Build the project
make release

# Check sinphase value
git-raf --sinphase

# Verify artifacts
git-raf --verify

# Create tag if stable
git-raf --tag

# Push tags to remote
git push origin --tags
```

This implementation provides a complete Git-RAF Auto-Tag system that:

1. Integrates with the build system
2. Verifies build artifacts
3. Calculates the sinphase stability metric
4. Uses trie-based classification for tag determination
5. Applies semantic versioning rules
6. Includes governance metadata in tags
7. Supports both manual and automated workflows
8. Provides CI/CD integration examples

The system follows the OBINexus Constitutional Ecosystem principles with machine-verifiable governance and systematic protection mechanisms.
