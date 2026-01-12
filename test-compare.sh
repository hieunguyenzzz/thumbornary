#!/bin/bash

# Thumbornary vs Cloudinary Comparison Test Script
# This script compares output from Thumbor against Cloudinary to ensure visual parity

set -e

# Configuration
CLOUDINARY_BASE="https://res.cloudinary.com/dfgbpib38/image/upload"
THUMBOR_BASE="${THUMBOR_BASE:-http://localhost:8080}"
OUTPUT_DIR="/tmp/thumbornary-tests"
VERBOSE=${VERBOSE:-0}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test cases: "transformations|origin|path"
TEST_CASES=(
    "w_1024,c_limit,q_auto|interior|cdn/shop/files/lifestyle_1888-1.jpg"
    "w_500|interior|cdn/shop/files/lifestyle_1888-1.jpg"
    "w_800,q_80|interior|cdn/shop/files/lifestyle_1888-1.jpg"
    "w_1200,c_limit|interior|cdn/shop/files/lifestyle_1888-1.jpg"
)

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local missing=0

    for cmd in curl identify compare; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        echo ""
        echo "Please install missing dependencies:"
        echo "  - curl: usually pre-installed"
        echo "  - identify/compare: brew install imagemagick (macOS) or apt install imagemagick (Linux)"
        exit 1
    fi
}

# Create output directory
setup() {
    mkdir -p "$OUTPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"
}

# Download image
download_image() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if curl -s -L -o "$output" -w "%{http_code}" "$url" | grep -q "200"; then
            return 0
        fi
        retry=$((retry + 1))
        sleep 1
    done

    return 1
}

# Get image dimensions
get_dimensions() {
    local file="$1"
    identify -format "%wx%h" "$file" 2>/dev/null || echo "unknown"
}

# Get file size in bytes
get_filesize() {
    local file="$1"
    stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
}

# Calculate SSIM (Structural Similarity Index)
# Returns value between 0 and 1, where 1 is identical
calculate_ssim() {
    local file1="$1"
    local file2="$2"

    # Use ImageMagick compare to get SSIM-like metric
    # Lower is better (0 = identical)
    local diff=$(compare -metric SSIM "$file1" "$file2" /dev/null 2>&1 || echo "0")
    echo "$diff"
}

# Run a single test
run_test() {
    local test_case="$1"
    local test_num="$2"

    # Parse test case
    IFS='|' read -r transformations origin path <<< "$test_case"

    local test_name="test_${test_num}"
    local cloudinary_url="${CLOUDINARY_BASE}/${transformations}/${origin}/${path}"
    local thumbor_url="${THUMBOR_BASE}/${transformations}/${origin}/${path}"
    local cloudinary_file="${OUTPUT_DIR}/${test_name}_cloudinary.jpg"
    local thumbor_file="${OUTPUT_DIR}/${test_name}_thumbor.jpg"
    local diff_file="${OUTPUT_DIR}/${test_name}_diff.jpg"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test $test_num: ${transformations}/${origin}/..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ $VERBOSE -eq 1 ]; then
        echo "Cloudinary: $cloudinary_url"
        echo "Thumbor:    $thumbor_url"
    fi

    # Download Cloudinary image
    log_info "Downloading from Cloudinary..."
    if ! download_image "$cloudinary_url" "$cloudinary_file"; then
        log_error "Failed to download from Cloudinary"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    # Download Thumbor image
    log_info "Downloading from Thumbor..."
    if ! download_image "$thumbor_url" "$thumbor_file"; then
        log_error "Failed to download from Thumbor (is it running?)"
        FAILED=$((FAILED + 1))
        return
    fi

    # Get metrics
    local cloudinary_dims=$(get_dimensions "$cloudinary_file")
    local thumbor_dims=$(get_dimensions "$thumbor_file")
    local cloudinary_size=$(get_filesize "$cloudinary_file")
    local thumbor_size=$(get_filesize "$thumbor_file")

    # Calculate size difference percentage
    local size_diff=0
    if [ "$cloudinary_size" -gt 0 ]; then
        size_diff=$(echo "scale=2; (($thumbor_size - $cloudinary_size) / $cloudinary_size) * 100" | bc)
    fi

    # Results
    echo ""
    echo "┌────────────────┬──────────────────┬──────────────────┐"
    echo "│ Metric         │ Cloudinary       │ Thumbor          │"
    echo "├────────────────┼──────────────────┼──────────────────┤"
    printf "│ Dimensions     │ %-16s │ %-16s │\n" "$cloudinary_dims" "$thumbor_dims"
    printf "│ File Size      │ %-16s │ %-16s │\n" "${cloudinary_size} bytes" "${thumbor_size} bytes"
    printf "│ Size Diff      │ %-16s │ %-16s │\n" "baseline" "${size_diff}%"
    echo "└────────────────┴──────────────────┴──────────────────┘"

    # Check dimensions match
    local dims_match=1
    if [ "$cloudinary_dims" != "$thumbor_dims" ]; then
        dims_match=0
        log_error "Dimensions mismatch!"
    fi

    # Check size is within ±20%
    local size_ok=1
    local abs_diff=${size_diff#-}  # Remove negative sign
    if (( $(echo "$abs_diff > 20" | bc -l) )); then
        size_ok=0
        log_warn "File size differs by more than 20%"
    fi

    # Calculate SSIM if dimensions match
    if [ $dims_match -eq 1 ]; then
        log_info "Calculating visual similarity..."
        local ssim=$(calculate_ssim "$cloudinary_file" "$thumbor_file")
        echo "SSIM Score: $ssim (closer to 1 is better)"

        # Generate diff image
        compare "$cloudinary_file" "$thumbor_file" "$diff_file" 2>/dev/null || true
        echo "Diff image: $diff_file"
    fi

    # Final verdict
    echo ""
    if [ $dims_match -eq 1 ] && [ $size_ok -eq 1 ]; then
        log_pass "Test PASSED"
        PASSED=$((PASSED + 1))
    else
        log_error "Test FAILED"
        FAILED=$((FAILED + 1))
    fi

    # Save URLs for reference
    echo "$cloudinary_url" > "${OUTPUT_DIR}/${test_name}_cloudinary.url"
    echo "$thumbor_url" > "${OUTPUT_DIR}/${test_name}_thumbor.url"
}

# Main
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║           Thumbornary vs Cloudinary Comparison Test Suite               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    check_dependencies
    setup

    log_info "Thumbor endpoint: $THUMBOR_BASE"
    log_info "Running ${#TEST_CASES[@]} test(s)..."

    local test_num=1
    for test_case in "${TEST_CASES[@]}"; do
        run_test "$test_case" "$test_num"
        test_num=$((test_num + 1))
    done

    # Summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                              Test Summary                                ║"
    echo "╠══════════════════════════════════════════════════════════════════════════╣"
    printf "║  Passed:  %-5d                                                         ║\n" $PASSED
    printf "║  Failed:  %-5d                                                         ║\n" $FAILED
    printf "║  Skipped: %-5d                                                         ║\n" $SKIPPED
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Test outputs saved to: $OUTPUT_DIR"
    echo ""

    # Exit with error if any tests failed
    if [ $FAILED -gt 0 ]; then
        exit 1
    fi
}

# Run main
main "$@"
