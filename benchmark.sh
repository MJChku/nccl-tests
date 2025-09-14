#!/bin/bash

# NCCL Benchmark Suite Wrapper
# Simple interface for running NCCL benchmarks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Function to convert size string to bytes
size_to_bytes() {
    local size="$1"
    case "$size" in
        *K|*k) echo $((${size%[Kk]} * 1024)) ;;
        *M|*m) echo $((${size%[Mm]} * 1024 * 1024)) ;;
        *G|*g) echo $((${size%[Gg]} * 1024 * 1024 * 1024)) ;;
        *) echo "$size" ;;  # assume bytes
    esac
}

# Function to convert bytes back to human readable size
bytes_to_size() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        echo "$((bytes / 1073741824))G"
    elif (( bytes >= 1048576 )); then
        echo "$((bytes / 1048576))M"
    elif (( bytes >= 1024 )); then
        echo "$((bytes / 1024))K"
    else
        echo "${bytes}"
    fi
}

# Function to generate doubling size range
generate_size_range() {
    local start_size="$1"
    local end_size="$2"
    
    local start_bytes=$(size_to_bytes "$start_size")
    local end_bytes=$(size_to_bytes "$end_size")
    
    if (( start_bytes > end_bytes )); then
        print_error "Start size ($start_size = $start_bytes bytes) must be <= end size ($end_size = $end_bytes bytes)"
        return 1
    fi
    
    local current_bytes=$start_bytes
    local sizes=()
    
    while (( current_bytes <= end_bytes )); do
        sizes+=($(bytes_to_size $current_bytes))
        current_bytes=$((current_bytes * 2))
    done
    
    echo "${sizes[@]}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing=0
    
    if [[ ! -f "run_nccl_benchmark.sh" ]]; then
        print_error "run_nccl_benchmark.sh not found"
        missing=1
    fi
    
    if [[ ! -f "parse_nccl_profile.py" ]]; then
        print_error "parse_nccl_profile.py not found" 
        missing=1
    fi
    
    if [[ ! -f "run.mk" ]]; then
        print_error "run.mk not found"
        missing=1
    fi
    
    if ! command -v bc &> /dev/null; then
        print_error "bc calculator not installed. Run: sudo apt-get install bc"
        missing=1
    fi
    
    if ! command -v python3 &> /dev/null; then
        print_error "python3 not installed"
        missing=1
    fi
    
    # Check if NCCL tests are built
    if [[ ! -d "build" ]]; then
        print_warn "build directory not found. You may need to build NCCL tests first."
        print_info "To build: make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi -B -j"
    fi
    
    if [[ $missing -eq 1 ]]; then
        print_error "Prerequisites not met. Please fix the above issues."
        exit 1
    fi
    
    print_success "All prerequisites met!"
}

# Show usage
show_usage() {
    cat << EOF
NCCL Benchmark Suite

USAGE:
  $0 [COMMAND] [OPTIONS]

COMMANDS:
  full                Run full benchmark suite (all collectives, all sizes)
  quick               Run quick test (subset of collectives and sizes)  
  single              Run single test configuration
  range               Run single collective with range of sizes (doubling progression)
  list                List available collectives and sizes
  clean [-f]          Remove all benchmark results, logs, and profile files
  lock-freq           Lock GPU frequencies for stable benchmarking
  unlock-freq         Restore automatic GPU frequency management
  help                Show this help message

OPTIONS:
  -c, --collective    Specify collective (broadcast, allreduce, etc.)
  -s, --size         Specify data size (8, 1K, 1M, etc.)
  --start            Specify start size for range mode (e.g., 1K)
  --end              Specify end size for range mode (e.g., 16M)
  -m, --mode         Specify mode (emulated, native, or both)
  -o, --output       Specify output directory name

EXAMPLES:
  $0 full                                    # Run complete benchmark suite
  $0 quick                                  # Run quick test
  $0 single -c broadcast -s 1M -m emulated # Run single test
  $0 single -c allreduce -s 4M             # Run both emulated and native
  $0 range -c broadcast --start 1K --end 16M # Run broadcast: 1K, 2K, 4K, 8K, 16M  
  $0 range -c all_reduce --start 256K --end 4M -m native # Native only, doubling from 256K to 4M
  $0 list                                   # Show available options
  $0 clean                                  # Remove all previous results and logs  
  $0 clean -f                               # Force clean without confirmation
  $0 lock-freq                              # Lock GPU frequencies for stable results
  $0 unlock-freq                            # Restore automatic frequency management

RESULTS:
  Results are saved in timestamped directories like:
  benchmark_results_YYYYMMDD_HHMMSS/
  
  Key files:
  - simple_results.txt             # Main results (CSV format)
  - benchmark_summary_report.txt   # Human-readable summary
  - benchmark_config.txt           # Test configuration and GPU status
  - individual test logs and profiles

PERFORMANCE:
  - GPU frequencies are automatically locked during benchmarks for consistency
  - Frequencies are restored after benchmark completion
  - Use lock-freq/unlock-freq commands for manual frequency control
  - MPI failures are automatically retried (up to 3 attempts)

EOF
}

# List available options
list_options() {
    print_info "Available NCCL Collectives:"
    echo "  - alltoall"
    echo "  - gather"
    echo "  - hypercube"  
    echo "  - sendrecv"
    echo "  - all_gather"
    echo "  - reduce"
    echo "  - reduce_scatter"
    echo "  - scatter"
    echo "  - all_reduce"
    echo "  - broadcast"
    echo
    
    print_info "Available Data Sizes:"
    echo "  - 8       (8 bytes)"
    echo "  - 1K      (1 KB)"
    echo "  - 4K      (4 KB)"
    echo "  - 16K     (16 KB)"
    echo "  - 64K     (64 KB)"
    echo "  - 256K    (256 KB)"
    echo "  - 1M      (1 MB)"
    echo "  - 4M      (4 MB)"
    echo "  - 16M     (16 MB)"
    echo "  - 48M     (48 MB)"
    echo
    
    print_info "Available Modes:"
    echo "  - emulated    (NEX CUDA emulation)"
    echo "  - native      (Native CUDA)"
    echo "  - both        (Run both modes)"
}

# Clean all benchmark files and logs
clean_all() {
    local force_clean=false
    
    # Check for force flag
    if [[ "$1" == "-f" || "$1" == "--force" ]]; then
        force_clean=true
        shift
    fi
    
    print_info "Cleaning all benchmark results, logs, and profile files..."
    
    local items_to_clean=()
    local directories_found=0
    local files_found=0
    local total_size=0
    
    # Check benchmark result directories
    if ls -d benchmark_results_* >/dev/null 2>&1; then
        for dir in benchmark_results_*; do
            if [[ -d "$dir" ]]; then
                items_to_clean+=("$dir/")
                directories_found=$((directories_found + 1))
                # Calculate directory size
                local dir_size=$(du -sk "$dir" 2>/dev/null | cut -f1 || echo "0")
                total_size=$((total_size + dir_size))
            fi
        done
    fi
    
    # Individual scattered log and profile files in main directory
    local file_patterns=(
        "*.log"
        "nccl_*.json" 
        "*.csv"
        "mpi-one-rank-*.out"
        "kernel_profile_*.json"
        "debug_*.log"
    )
    
    for pattern in "${file_patterns[@]}"; do
        # Use ls to check if files match pattern (safer than using glob directly)
        if ls $pattern >/dev/null 2>&1; then
            for file in $pattern; do
                if [[ -f "$file" ]]; then
                    items_to_clean+=("$file")
                    files_found=$((files_found + 1))
                    # Add file size
                    local file_size=$(du -sk "$file" 2>/dev/null | cut -f1 || echo "0")
                    total_size=$((total_size + file_size))
                fi
            done
        fi
    done
    
    # Also clean temporary files
    if [[ -f "/tmp/parse_output.txt" ]]; then
        items_to_clean+=("/tmp/parse_output.txt")
        files_found=$((files_found + 1))
    fi
    
    # Show what will be cleaned
    if [[ ${#items_to_clean[@]} -eq 0 ]]; then
        print_success "✨ No benchmark files found to clean - workspace is already clean!"
        return 0
    fi
    
    # Convert size to human readable
    local human_size=""
    if [[ $total_size -gt 1048576 ]]; then
        human_size=$(echo "scale=1; $total_size / 1048576" | bc -l)"GB"
    elif [[ $total_size -gt 1024 ]]; then
        human_size=$(echo "scale=1; $total_size / 1024" | bc -l)"MB"
    else
        human_size="${total_size}KB"
    fi
    
    echo
    print_info "📊 Cleanup Summary:"
    print_info "  📁 Result directories: $directories_found"
    print_info "  📄 Scattered files: $files_found"
    print_info "  💾 Total size: ~$human_size"
    
    if [[ "$force_clean" = false ]]; then
        echo
        print_warn "🗑️  Preview of items to be deleted:"
        
        local preview_count=0
        for item in "${items_to_clean[@]}"; do
            if [[ $preview_count -lt 10 ]]; then
                echo "    $item"
                preview_count=$((preview_count + 1))
            fi
        done
        
        if [[ ${#items_to_clean[@]} -gt 10 ]]; then
            echo "    ... and $((${#items_to_clean[@]} - 10)) more items"
        fi
        
        echo
        read -p "Are you sure you want to delete all these items? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Cleanup cancelled"
            return 0
        fi
    fi
    
    print_info "🧹 Cleaning in progress..."
    
    local cleaned_dirs=0
    local cleaned_files=0
    
    # Remove directories
    if [[ $directories_found -gt 0 ]]; then
        for dir in benchmark_results_*; do
            if [[ -d "$dir" ]]; then
                rm -rf "$dir" 2>/dev/null && cleaned_dirs=$((cleaned_dirs + 1))
            fi
        done
        if [[ $cleaned_dirs -gt 0 ]]; then
            print_success "✓ Removed $cleaned_dirs result directories"
        fi
    fi
    
    # Remove scattered files
    for pattern in "${file_patterns[@]}"; do
        if ls $pattern >/dev/null 2>&1; then
            for file in $pattern; do
                if [[ -f "$file" ]]; then
                    rm -f "$file" 2>/dev/null && cleaned_files=$((cleaned_files + 1))
                fi
            done
        fi
    done
    
    # Clean temp files
    rm -f /tmp/parse_output.txt 2>/dev/null || true
    
    if [[ $cleaned_files -gt 0 ]]; then
        print_success "✓ Removed $cleaned_files scattered log/profile files"
    fi
    
    print_success "🎉 Cleanup completed successfully!"
    print_info "Freed up approximately $human_size of disk space"
    print_info "Next benchmark will start with a clean workspace"
    echo
    print_info "💡 Tips:"
    print_info "  • Use 'clean -f' to skip confirmation prompt"
    print_info "  • All results are organized in timestamped directories"
    print_info "  • Run 'list' to see available test options"
}

# Run full benchmark
run_full() {
    print_info "Starting full benchmark suite..."
    print_warn "This will take a long time (potentially hours)"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        exit 0
    fi
    
    ./run_nccl_benchmark.sh "$@"
}

# Run quick test
run_quick() {
    print_info "Starting quick benchmark test..."
    print_info "Testing: broadcast, allreduce with sizes 1K, 1M, 16M"
    
    # Run broadcast tests
    print_info "Testing broadcast..."
    ./run_nccl_benchmark.sh -c broadcast -s 1K "$@" &&
    ./run_nccl_benchmark.sh -c broadcast -s 1M "$@" &&
    ./run_nccl_benchmark.sh -c broadcast -s 16M "$@" &&
    
    # Run allreduce tests  
    print_info "Testing allreduce..."
    ./run_nccl_benchmark.sh -c all_reduce -s 1K "$@" &&
    ./run_nccl_benchmark.sh -c all_reduce -s 1M "$@" &&
    ./run_nccl_benchmark.sh -c all_reduce -s 16M "$@"
}

# Run range test (single collective, multiple sizes with doubling progression)
run_range() {
    local collective=""
    local start_size="1K"  # default start
    local end_size="16M"   # default end
    local mode=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--collective)
                collective="$2"
                shift 2
                ;;
            --start)
                start_size="$2"
                shift 2
                ;;
            --end)
                end_size="$2"
                shift 2
                ;;
            -m|--mode)
                mode="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate inputs
    if [[ -z "$collective" ]]; then
        print_error "Collective not specified. Use -c option."
        print_info "Available collectives: broadcast, all_reduce, gather, etc."
        exit 1
    fi
    
    # Generate size range
    local sizes
    if ! sizes=$(generate_size_range "$start_size" "$end_size"); then
        exit 1
    fi
    
    print_info "Running range test for $collective from $start_size to $end_size"
    print_info "Size progression: $sizes"
    print_info "Mode: ${mode:-both}"
    
    # Arrays to collect results for summary
    declare -a size_results=()
    declare -a emulated_times=()
    declare -a native_times=()
    declare -a ratios=()
    
    # Run tests for each size in the range with retry logic
    for size in $sizes; do
        local cmd="./run_nccl_benchmark.sh -c $collective -s $size"
        if [[ -n "$mode" && "$mode" != "both" ]]; then
            cmd="$cmd -m $mode"
        fi
        
        print_info "Testing size: $size"
        
        # Retry logic for MPI failures
        local retry_count=0
        local max_retries=3
        local success=false
        
        while [[ $retry_count -lt $max_retries && "$success" = false ]]; do
            if eval "$cmd"; then
                success=true
                
                # Extract results from the latest results directory
                local latest_results=$(ls -td benchmark_results_* 2>/dev/null | head -1)
                if [[ -n "$latest_results" && -f "$latest_results/simple_results.txt" ]]; then
                    # Parse emulated and native results for this size
                    local emulated_time=$(grep "^$collective,$size,emulated," "$latest_results/simple_results.txt" | cut -d',' -f4 2>/dev/null)
                    local native_time=$(grep "^$collective,$size,native," "$latest_results/simple_results.txt" | cut -d',' -f4 2>/dev/null)
                    
                    # Store results if both are available and non-zero
                    if [[ -n "$emulated_time" && -n "$native_time" && "$emulated_time" != "0" && "$native_time" != "0" ]]; then
                        # Calculate ratio (emulated/native)
                        local ratio=$(echo "scale=2; $emulated_time / $native_time" | bc -l 2>/dev/null || echo "N/A")
                        
                        # Store results
                        size_results+=("$size")
                        emulated_times+=("$emulated_time")
                        native_times+=("$native_time") 
                        ratios+=("$ratio")
                        
                        print_success "✓ $size: Emulated=${emulated_time}ms, Native=${native_time}ms, Ratio=${ratio}x"
                    else
                        print_warn "⚠ $size: Incomplete results (emulated=$emulated_time, native=$native_time)"
                    fi
                fi
            else
                retry_count=$((retry_count + 1))
                if [[ $retry_count -lt $max_retries ]]; then
                    print_warn "✗ Test failed for size $size, retrying ($retry_count/$max_retries)..."
                    sleep 3
                else
                    print_error "✗ Test failed for size $size after $max_retries attempts"
                    size_results+=("$size")
                    emulated_times+=("FAILED")
                    native_times+=("FAILED")
                    ratios+=("N/A")
                fi
            fi
        done
        
        # Brief pause between sizes
        sleep 1
    done
    
    # Print comprehensive results summary
    echo
    print_success "=== Range Test Summary: $collective ($start_size to $end_size) ==="
    printf "${BLUE}%-10s %-15s %-15s %-12s${NC}\n" "Size" "Emulated(ms)" "Native(ms)" "Ratio"
    printf "%-10s %-15s %-15s %-12s\n" "----------" "---------------" "---------------" "------------"
    
    for i in "${!size_results[@]}"; do
        local size="${size_results[$i]}"
        local emulated="${emulated_times[$i]}"
        local native="${native_times[$i]}"
        local ratio="${ratios[$i]}"
        
        # Color coding based on status
        if [[ "$emulated" == "FAILED" ]]; then
            printf "${RED}%-10s %-15s %-15s %-12s${NC}\n" "$size" "$emulated" "$native" "$ratio"
        else
            printf "%-10s %-15s %-15s %-12s\n" "$size" "$emulated" "$native" "$ratio"
        fi
    done
    
    # Calculate and show performance trends (only for successful tests)
    local valid_ratios=()
    for ratio in "${ratios[@]}"; do
        if [[ "$ratio" != "N/A" && "$ratio" != "0" ]]; then
            valid_ratios+=("$ratio")
        fi
    done
    
    if [[ ${#valid_ratios[@]} -gt 0 ]]; then
        local min_ratio=${valid_ratios[0]}
        local max_ratio=${valid_ratios[0]}
        local total_ratio=0
        
        for ratio in "${valid_ratios[@]}"; do
            total_ratio=$(echo "scale=6; $total_ratio + $ratio" | bc -l)
            if (( $(echo "$ratio < $min_ratio" | bc -l) )); then
                min_ratio=$ratio
            fi
            if (( $(echo "$ratio > $max_ratio" | bc -l) )); then
                max_ratio=$ratio
            fi
        done
        
        local avg_ratio=$(echo "scale=2; $total_ratio / ${#valid_ratios[@]}" | bc -l)
        
        echo
        print_info "📊 Performance Analysis:"
        print_info "   Average emulation overhead: ${avg_ratio}x"
        print_info "   Best case overhead: ${min_ratio}x"
        print_info "   Worst case overhead: ${max_ratio}x"
        
        if (( $(echo "$min_ratio < 10" | bc -l) )); then
            print_success "   ✓ Emulation overhead under 10x for best case"
        fi
        if (( $(echo "$avg_ratio < 20" | bc -l) )); then
            print_success "   ✓ Average emulation overhead under 20x"
        else
            print_warn "   ⚠ High average emulation overhead (>20x)"
        fi
    fi
    
    print_success "Range test completed: ${#size_results[@]} sizes tested, ${#valid_ratios[@]} successful"
}

# Run single test
run_single() {
    local collective=""
    local size=""
    local mode=""
    local output=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--collective)
                collective="$2"
                shift 2
                ;;
            -s|--size)
                size="$2"
                shift 2
                ;;
            -m|--mode)
                mode="$2"
                shift 2
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate inputs
    if [[ -z "$collective" ]]; then
        print_error "Collective not specified. Use -c option."
        print_info "Available collectives: broadcast, all_reduce, gather, etc."
        exit 1
    fi
    
    if [[ -z "$size" ]]; then
        print_error "Size not specified. Use -s option."
        print_info "Available sizes: 8, 1K, 1M, 16M, etc."
        exit 1
    fi
    
    # Build command
    local cmd="./run_nccl_benchmark.sh -c $collective -s $size"
    if [[ -n "$mode" && "$mode" != "both" ]]; then
        cmd="$cmd -m $mode"
    fi
    
    print_info "Running single test: collective=$collective, size=$size, mode=${mode:-both}"
    eval "$cmd"
}

# Main execution
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        full)
            check_prerequisites
            run_full "$@"
            ;;
        quick)
            check_prerequisites
            run_quick "$@"
            ;;
        single)
            check_prerequisites
            run_single "$@"
            ;;
        range)
            check_prerequisites
            run_range "$@"
            ;;
        list)
            list_options
            ;;
        clean)
            clean_all "$@"
            ;;
        lock-freq)
            if [[ -x "./lock_freq.sh" ]]; then
                print_info "🔒 Locking GPU frequencies for stable benchmarking..."
                ./lock_freq.sh
            else
                print_error "lock_freq.sh not found or not executable"
                exit 1
            fi
            ;;
        unlock-freq)
            if [[ -x "./unlock_freq.sh" ]]; then
                print_info "🔓 Unlocking GPU frequencies..."
                ./unlock_freq.sh
            else
                print_error "unlock_freq.sh not found or not executable"  
                exit 1
            fi
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
