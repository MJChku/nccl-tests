#!/bin/bash

# NCCL Benchmark Configuration
# Edit this file to customize which tests to run

# Collective operations to test (comment out to disable)
COLLECTIVES_TO_TEST=(
    "alltoall"
    "gather" 
    "hypercube"
    "sendrecv"
    "all_gather"
    "reduce"
    "reduce_scatter"
    "scatter"
    "all_reduce"
    "broadcast"
)

# Data sizes to test
SIZES_TO_TEST=(
    "8"       # 8 bytes
    "1K"      # 1 KB
    "4K"      # 4 KB  
    "16K"     # 16 KB
    "64K"     # 64 KB
    "256K"    # 256 KB
    "1M"      # 1 MB
    "4M"      # 4 MB
    "16M"     # 16 MB
    "48M"     # 48 MB
)

# Special sizes for gather (requires smaller sizes)
GATHER_SIZES_TO_TEST=(
    "8"
    "64"
    "256"
    "1K"
    "4K"
    "16K"
    "64K"
)

# Test modes (comment out to disable)
MODES_TO_TEST=(
    "emulated"  # NEX CUDA emulation
    "native"    # Native CUDA
)

# Test configuration
MAX_TEST_DURATION=300  # seconds per test (5 minutes)
PAUSE_BETWEEN_TESTS=2  # seconds

# Output configuration
GENERATE_DETAILED_LOGS=true
GENERATE_CSV_OUTPUT=true
GENERATE_SUMMARY_REPORT=true

# Quick test configuration (smaller subset for fast testing)
QUICK_TEST_COLLECTIVES=(
    "broadcast"
    "all_reduce"
)

QUICK_TEST_SIZES=(
    "1K"
    "1M"
    "16M"
)

# Function to get collectives based on mode
get_test_collectives() {
    local quick_mode="$1"
    if [[ "$quick_mode" == "true" ]]; then
        echo "${QUICK_TEST_COLLECTIVES[@]}"
    else
        echo "${COLLECTIVES_TO_TEST[@]}"
    fi
}

# Function to get sizes based on mode and collective
get_test_sizes() {
    local quick_mode="$1"
    local collective="$2"
    
    if [[ "$quick_mode" == "true" ]]; then
        echo "${QUICK_TEST_SIZES[@]}"
    elif [[ "$collective" == "gather" ]]; then
        echo "${GATHER_SIZES_TO_TEST[@]}"
    else
        echo "${SIZES_TO_TEST[@]}"
    fi
}

echo "NCCL Benchmark Configuration Loaded"
echo "Collectives: ${#COLLECTIVES_TO_TEST[@]} configured"
echo "Sizes: ${#SIZES_TO_TEST[@]} configured" 
echo "Modes: ${#MODES_TO_TEST[@]} configured"
