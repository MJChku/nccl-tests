#!/bin/bash

# NCCL Collective Operations Benchmark Suite
# This script runs all NCCL collective operations with various sizes,
# comparing NEX emulated vs native CUDA performance

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Test configurations
declare -A COLLECTIVES=(
    # ["alltoall"]="./build/alltoall_perf"
    # ["gather"]="./build/gather_perf"
    # ["hypercube"]="./build/hypercube_perf" 
    ["sendrecv"]="./build/sendrecv_perf"
    ["all_gather"]="./build/all_gather_perf"
    ["reduce"]="./build/reduce_perf"
    ["reduce_scatter"]="./build/reduce_scatter_perf"
    ["broadcast"]="./build/broadcast_perf"
    # ["scatter"]="./build/scatter_perf"
    ["all_reduce"]="./build/all_reduce_perf"
)

# Size configurations (in bytes)
SIZES=("8" "1K" "4K" "16K" "64K" "256K" "1M" "4M" "16M" "48M")

# Special cases for gather (needs smaller sizes)
GATHER_SIZES=("8" "64" "256" "1K" "4K" "16K" "64K")

# Results directory
RESULTS_DIR="benchmark_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

# CSV results file
RESULTS_CSV="$RESULTS_DIR/nccl_benchmark_summary.csv"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$RESULTS_DIR/benchmark.log"
}

# Function to create temporary run.mk with specific target and meaningful profile names
create_run_mk() {
    local collective="$1"
    local size="$2"
    local mode="$3"
    local temp_mk="/tmp/run_${collective}_${size}_${mode}.mk"
    
    # Generate meaningful profile filename prefix
    local profile_prefix
    if [[ "$mode" == "emulated" ]]; then
        profile_prefix="nccl_${collective}_${size}_emulated_r"
    else
        profile_prefix="nccl_${collective}_${size}_native_r" 
    fi
    
    # Copy original run.mk and update TARGET_MPI_ONE and profile filenames
    sed "s|^TARGET_MPI_ONE=.*|TARGET_MPI_ONE=${COLLECTIVES[$collective]} -b $size -e $size -g 1 -w 0 -n 1 |" run.mk | \
    sed "s|nccl_sim_profile_r\$\$OMPI_COMM_WORLD_RANK|${profile_prefix}\$\$OMPI_COMM_WORLD_RANK|g" | \
    sed "s|nccl_native_profile_r\$\$OMPI_COMM_WORLD_RANK|${profile_prefix}\$\$OMPI_COMM_WORLD_RANK|g" > "$temp_mk"
    
    echo "$temp_mk"
}

# Function to run a single test configuration
run_test() {
    local collective="$1"
    local size="$2"
    local mode="$3"  # "emulated" or "native"
    
    log "Running $collective with size $size in $mode mode"
    
    # Create temporary makefile with meaningful profile names
    local temp_mk
    temp_mk=$(create_run_mk "$collective" "$size" "$mode")
    
    # Determine make target
    local make_target
    if [[ "$mode" == "emulated" ]]; then
        make_target="run"
    else
        make_target="run-native"
    fi
    
    # Clean up old profile files and logs to avoid confusion
    rm -f nccl_*_profile_*.json mpi-one-rank-*.out nccl_*.json
    rm -f kernel_profile_*.json  # Also clean up any kernel profile files
    
    # Run the test with retry logic for MPI faults
    local test_start=$(date +%s)
    local retry_count=0
    local max_retries=3
    local make_success=false
    
    while [[ $retry_count -lt $max_retries && "$make_success" = false ]]; do
        log "Running test attempt $((retry_count + 1))/$max_retries for $collective $size $mode"
        
        # Clean up any previous attempt artifacts
        if [[ $retry_count -gt 0 ]]; then
            rm -f nccl_*_profile_*.json mpi-one-rank-*.out nccl_*.json
            rm -f kernel_profile_*.json
            sleep 2  # Brief pause before retry
        fi
        
        if timeout 300 make -f "$temp_mk" "$make_target" > "$RESULTS_DIR/${collective}_${size}_${mode}_attempt$((retry_count + 1)).log" 2>&1; then
            make_success=true
            log "Test succeeded on attempt $((retry_count + 1))"
        else
            # Check if this was an MPI fault by examining the log
            local log_file="$RESULTS_DIR/${collective}_${size}_${mode}_attempt$((retry_count + 1)).log"
            if grep -q "Segmentation fault\|MPI_\|mpirun.*error\|ORTE_ERROR\|Signal: Segmentation fault" "$log_file" 2>/dev/null; then
                retry_count=$((retry_count + 1))
                if [[ $retry_count -lt $max_retries ]]; then
                    log "MPI fault detected, retrying ($retry_count/$max_retries)..."
                else
                    log "MPI fault persists after $max_retries attempts"
                fi
            else
                # Non-MPI error, don't retry
                log "Non-MPI error detected, not retrying"
                break
            fi
        fi
    done
    
    if [[ "$make_success" = true ]]; then
        # Copy the successful log to the main log file
        cp "$RESULTS_DIR/${collective}_${size}_${mode}_attempt"*.log "$RESULTS_DIR/${collective}_${size}_${mode}.log" 2>/dev/null || true
        # Extract average bus bandwidth (GB/s) from the test log if present
        local bus_bw=0
        local main_log="$RESULTS_DIR/${collective}_${size}_${mode}.log"
        if [[ -f "$main_log" ]]; then
            bus_bw=$(grep -E "Avg bus bandwidth[[:space:]]*:[[:space:]]*[0-9]+(\.[0-9]+)?" "$main_log" 2>/dev/null | tail -n1 | sed -E 's/.*:[[:space:]]*([0-9.]+).*/\1/') || true
            if [[ -z "$bus_bw" ]]; then
                bus_bw=0
            fi
        fi
        local test_end=$(date +%s)
        local test_duration=$((test_end - test_start))
        log "Test completed in ${test_duration}s"
        
        # Find NCCL profile files created after test started
        local profile_files
        if [[ "$mode" == "emulated" ]]; then
            # Look for the new naming pattern with RANK variable
            profile_files=$(find . -maxdepth 1 -name "nccl_${collective}_${size}_${mode}_r*.json" -newer "$temp_mk" 2>/dev/null || true)
        else
            # Native mode - look for the new naming pattern
            profile_files=$(find . -maxdepth 1 -name "nccl_${collective}_${size}_${mode}_r*.json" -newer "$temp_mk" 2>/dev/null || true)
        fi
        
        # Only use NCCL profiler files, ignore NEX kernel profiles
        local all_profiles="$profile_files"
        
        if [[ -n "$all_profiles" && "$all_profiles" != " " ]]; then
            # Parse each profile file and extract kernel durations
            local total_duration=0
            local kernel_count=0
            
            for profile_file in $all_profiles; do
                if [[ -f "$profile_file" && -s "$profile_file" ]]; then
                    log "Parsing profile: $profile_file"
                    
                    # Parse with our Python script (no CSV needed)
                    if python3 parse_nccl_profile.py "$profile_file" > "/tmp/parse_output.txt" 2>&1; then
                        # Extract average duration from the parsing output
                        local avg_duration
                        avg_duration=$(grep "Overall average kernel duration:" "/tmp/parse_output.txt" | sed -n 's/.*Overall average kernel duration: \([0-9.]*\)ms.*/\1/p')
                        
                        if [[ -n "$avg_duration" ]]; then
                            total_duration=$(echo "$total_duration + $avg_duration" | bc -l)
                            kernel_count=$((kernel_count + 1))
                            log "Found average kernel duration: ${avg_duration}ms"
                        fi
                    else
                        log "Warning: Failed to parse profile $profile_file"
                    fi
                    
                    # Rename profile file to include test info and move to results
                    local new_name="${collective}_${size}_${mode}_$(basename "$profile_file")"
                    mv "$profile_file" "$RESULTS_DIR/$new_name"
                    log "Saved profile as: $new_name"
                fi
            done
            
            # Also copy any kernel_profile files generated during this test
            local kernel_profiles
            kernel_profiles=$(find . -maxdepth 1 -name "kernel_profile_*.json" -newer "$temp_mk" 2>/dev/null || true)
            if [[ -n "$kernel_profiles" ]]; then
                for kernel_file in $kernel_profiles; do
                    if [[ -f "$kernel_file" ]]; then
                        local kernel_new_name="${collective}_${size}_${mode}_$(basename "$kernel_file")"
                        cp "$kernel_file" "$RESULTS_DIR/$kernel_new_name"
                        log "Saved kernel profile as: $kernel_new_name"
                    fi
                done
            fi
            
            # Calculate average across all profiles
            local final_avg_duration=0
            if [[ $kernel_count -gt 0 ]]; then
                final_avg_duration=$(echo "scale=6; $total_duration / $kernel_count" | bc -l)
            fi
            
            # Record result in simple format (no CSV). Append avg bus bandwidth (GB/s).
            echo "$collective,$size,$mode,$final_avg_duration,$kernel_count,$test_duration,$bus_bw" >> "$RESULTS_DIR/simple_results.txt"
            log "Average kernel duration: ${final_avg_duration}ms (from $kernel_count profiles)"
        else
            log "Warning: No profile files found for $collective $size $mode"
            echo "$collective,$size,$mode,0,0,$test_duration,$bus_bw" >> "$RESULTS_DIR/simple_results.txt"
        fi
    else
        log "Error: Test failed permanently for $collective $size $mode after $max_retries attempts"
        echo "$collective,$size,$mode,ERROR,0,300,0" >> "$RESULTS_DIR/simple_results.txt"
    fi
    
    # Cleanup
    rm -f "$temp_mk"
    rm -f /tmp/parse_output.txt
    # Clean up attempt logs (keep only the main log)
    # rm -f "$RESULTS_DIR/${collective}_${size}_${mode}_attempt"*.log
}

# Function to get sizes for a collective
get_sizes() {
    local collective="$1"
    if [[ "$collective" == "gather" ]]; then
        echo "${GATHER_SIZES[@]}"
    else
        echo "${SIZES[@]}"
    fi
}

# Main execution
main() {
    log "Starting NCCL benchmark suite"
    log "Results will be stored in: $RESULTS_DIR"
    
    # Lock GPU frequencies for consistent benchmarking
    if [[ -x "./lock_freq.sh" ]]; then
        log "Locking GPU frequencies for consistent benchmarking..."
        if ./lock_freq.sh; then
            log "✓ GPU frequencies locked successfully"
            echo "gpu_freq_locked=true" >> "$RESULTS_DIR/benchmark_config.txt"
        else
            log "⚠ Warning: Failed to lock GPU frequencies - benchmarks may have variable performance"
            echo "gpu_freq_locked=false" >> "$RESULTS_DIR/benchmark_config.txt"
        fi
    else
        log "⚠ Warning: lock_freq.sh not found or not executable - GPU frequencies not locked"
        echo "gpu_freq_locked=not_available" >> "$RESULTS_DIR/benchmark_config.txt"
    fi
    
    # Initialize simple results file header (added avg_bus_bandwidth_gbps)
    echo "collective,size,mode,avg_kernel_duration_ms,profile_count,test_duration_s,avg_bus_bandwidth_gbps" > "$RESULTS_DIR/simple_results.txt"
    
    # Check if parse_nccl_profile.py exists
    if [[ ! -f "parse_nccl_profile.py" ]]; then
        log "Error: parse_nccl_profile.py not found in current directory"
        exit 1
    fi
    
    # Check if bc is available for calculations
    if ! command -v bc &> /dev/null; then
        log "Error: bc calculator not found. Please install: sudo apt-get install bc"
        exit 1
    fi
    
    # Run tests for each collective
    for collective in "${!COLLECTIVES[@]}"; do
        log "=== Testing collective: $collective ==="
        
        # Get appropriate sizes for this collective
        local sizes_array
        IFS=' ' read -ra sizes_array <<< "$(get_sizes "$collective")"
        
        for size in "${sizes_array[@]}"; do
            log "--- Testing size: $size ---"
            
            # Run emulated version
            run_test "$collective" "$size" "emulated"
            
            # # Run native version
            # run_test "$collective" "$size" "native"
            
            # Brief pause between tests
            sleep 2
        done
    done
    
    log "=== Benchmark suite completed ==="
    log "Results summary saved to: $RESULTS_DIR/simple_results.txt"
    
    # Generate summary report
    generate_summary_report
}

# Function to generate summary report
generate_summary_report() {
    log "Generating summary report..."
    
    local report_file="$RESULTS_DIR/benchmark_summary_report.txt"
    
    {
        echo "NCCL Collective Operations Benchmark Report"
        echo "Generated: $(date)"
        echo "=========================================="
        echo
        
        # Overall statistics
        echo "Test Summary:"
        echo "- Total collectives tested: $(echo "${!COLLECTIVES[@]}" | wc -w)"
        echo "- Total size configurations: $(echo "${SIZES[@]}" | wc -w)"
        echo "- Results directory: $RESULTS_DIR"
        echo
        
        # Performance comparison by collective
        echo "Performance Comparison (Emulated vs Native):"
        echo "============================================="
        
        for collective in "${!COLLECTIVES[@]}"; do
            echo
            echo "Collective: $collective"
            echo "------------------------"

            if [[ -f "$RESULTS_DIR/simple_results.txt" ]]; then
                # Read all matching lines into an array so we can compute averages
                mapfile -t coll_lines < <(grep "^$collective," "$RESULTS_DIR/simple_results.txt" || true)
                local sum_bw=0
                local bw_count=0
                if [[ ${#coll_lines[@]} -eq 0 ]]; then
                    echo "  No results for $collective"
                else
                    for line in "${coll_lines[@]}"; do
                        IFS=',' read -r coll size mode duration profiles test_time bus_bw <<< "$line"
                        if [[ "$duration" != "ERROR" && "$duration" != "0" ]]; then
                            printf "  %-8s %-8s: %8.3f ms (%d profiles, %ds test) | Avg bus bw: %s GB/s\n" "$size" "$mode" "$duration" "$profiles" "$test_time" "$bus_bw"
                        else
                            printf "  %-8s %-8s: %s\n" "$size" "$mode" "$duration"
                        fi
                        if [[ -n "$bus_bw" && "$bus_bw" != "0" ]]; then
                            sum_bw=$(echo "$sum_bw + $bus_bw" | bc -l)
                            bw_count=$((bw_count+1))
                        fi
                    done
                    if [[ $bw_count -gt 0 ]]; then
                        avg_bw=$(echo "scale=3; $sum_bw / $bw_count" | bc -l)
                        echo "  Average bus bandwidth for $collective: ${avg_bw} GB/s (from $bw_count runs)"
                    else
                        echo "  Average bus bandwidth for $collective: N/A"
                    fi
                fi
            else
                echo "  No results file found"
            fi
        done

        # Compute overall average bus bandwidth across all runs (if any)
        if [[ -f "$RESULTS_DIR/simple_results.txt" ]]; then
            mapfile -t all_lines < <(tail -n +2 "$RESULTS_DIR/simple_results.txt" || true)
            total_bw=0
            total_count=0
            for l in "${all_lines[@]}"; do
                IFS=',' read -r _coll _size _mode _dur _prof _t bus <<< "$l"
                if [[ -n "$bus" && "$bus" != "0" ]]; then
                    total_bw=$(echo "$total_bw + $bus" | bc -l)
                    total_count=$((total_count+1))
                fi
            done
            if [[ $total_count -gt 0 ]]; then
                overall_avg_bw=$(echo "scale=3; $total_bw / $total_count" | bc -l)
                echo
                echo "Overall average bus bandwidth across all benchmarks: ${overall_avg_bw} GB/s (from $total_count runs)"
            fi
        fi
        
        echo
        echo "Detailed results available in: $RESULTS_DIR/simple_results.txt"
        echo "Individual test logs in: $RESULTS_DIR/"
        
    } > "$report_file"
    
    log "Summary report saved to: $report_file"
    
    # Unlock GPU frequencies after benchmarking
    if [[ -f "$RESULTS_DIR/benchmark_config.txt" ]] && grep -q "gpu_freq_locked=true" "$RESULTS_DIR/benchmark_config.txt"; then
        if [[ -x "./unlock_freq.sh" ]]; then
            log "Unlocking GPU frequencies..."
            if ./unlock_freq.sh; then
                log "✓ GPU frequencies unlocked - restored automatic management"
                echo "gpu_freq_unlocked=true" >> "$RESULTS_DIR/benchmark_config.txt"
            else
                log "⚠ Warning: Failed to unlock GPU frequencies - may need manual unlock"
                echo "gpu_freq_unlocked=false" >> "$RESULTS_DIR/benchmark_config.txt"
            fi
        else
            log "⚠ Warning: unlock_freq.sh not found - GPU frequencies remain locked"
            log "   Run './unlock_freq.sh' manually to restore automatic frequency management"
            echo "gpu_freq_unlocked=script_missing" >> "$RESULTS_DIR/benchmark_config.txt"
        fi
    fi
    
    # Display key results
    echo
    echo "=== Quick Summary ==="
    head -20 "$report_file"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --collective    Run specific collective only (e.g., broadcast,allreduce)"
    echo "  -s, --size          Run specific size only (e.g., 1M,4M)"
    echo "  -m, --mode          Run specific mode only (emulated or native)"
    echo
    echo "Examples:"
    echo "  $0                                    # Run all tests"
    echo "  $0 -c broadcast                      # Run only broadcast tests"
    echo "  $0 -c broadcast -s 1M               # Run broadcast with 1M size only"
    echo "  $0 -m native                        # Run only native tests"
}

# Command line parsing
SELECTED_COLLECTIVE=""
SELECTED_SIZE=""
SELECTED_MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--collective)
            SELECTED_COLLECTIVE="$2"
            shift 2
            ;;
        -s|--size)
            SELECTED_SIZE="$2"
            shift 2
            ;;
        -m|--mode)
            SELECTED_MODE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate selections
if [[ -n "$SELECTED_COLLECTIVE" && ! -v "COLLECTIVES[$SELECTED_COLLECTIVE]" ]]; then
    log "Error: Unknown collective '$SELECTED_COLLECTIVE'"
    log "Available collectives: ${!COLLECTIVES[*]}"
    exit 1
fi

if [[ -n "$SELECTED_MODE" && "$SELECTED_MODE" != "emulated" && "$SELECTED_MODE" != "native" ]]; then
    log "Error: Mode must be 'emulated' or 'native'"
    exit 1
fi

# Override arrays based on selections
if [[ -n "$SELECTED_COLLECTIVE" ]]; then
    declare -A SELECTED_COLLECTIVES
    SELECTED_COLLECTIVES["$SELECTED_COLLECTIVE"]="${COLLECTIVES[$SELECTED_COLLECTIVE]}"
    COLLECTIVES=()
    for key in "${!SELECTED_COLLECTIVES[@]}"; do
        COLLECTIVES["$key"]="${SELECTED_COLLECTIVES[$key]}"
    done
fi

if [[ -n "$SELECTED_SIZE" ]]; then
    SIZES=("$SELECTED_SIZE")
    GATHER_SIZES=("$SELECTED_SIZE")
fi

# Run main function
main "$@"
