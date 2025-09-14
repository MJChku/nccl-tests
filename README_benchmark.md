# NCCL Collective Operations Benchmark Suite

This benchmark suite automatically tests all NCCL collective operations, comparing NEX CUDA emulation performance against native CUDA performance.

## Features

- **Comprehensive Testing**: Tests all 10 NCCL collective operations
- **Multiple Data Sizes**: Tests various data sizes from 8 bytes to 48MB
- **Performance Comparison**: Compares emulated vs native CUDA performance
- **Automated Analysis**: Parses profiling data and generates summary reports
- **Configurable**: Easy to customize which tests to run
- **CSV Output**: Results in machine-readable format for further analysis

## Quick Start

```bash
# Check prerequisites and run quick test
./benchmark.sh quick

# Run single test
./benchmark.sh single -c broadcast -s 1M

# Run full benchmark suite (takes hours)
./benchmark.sh full

# List available options
./benchmark.sh list
```

## Files Overview

- `benchmark.sh` - Main user interface script
- `run_nccl_benchmark.sh` - Core benchmark execution engine
- `parse_nccl_profile.py` - NCCL profiling data parser
- `benchmark_config.sh` - Configuration settings
- `run.mk` - Makefile for NCCL test execution

## Prerequisites

1. **Build NCCL Tests**:
   ```bash
   make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi -B -j
   ```

2. **Install Dependencies**:
   ```bash
   sudo apt-get install bc python3
   ```

3. **Ensure NEX is Built**: The NEX CUDA emulation library should be available

## Usage Examples

### Quick Test (Recommended First)
```bash
./benchmark.sh quick
```
Tests broadcast and allreduce with 3 different sizes. Takes ~10-15 minutes.

### Single Collective Test
```bash
# Test broadcast with 1MB data
./benchmark.sh single -c broadcast -s 1M

# Test allreduce with 16MB data, emulated mode only
./benchmark.sh single -c all_reduce -s 16M -m emulated
```

### Full Benchmark Suite
```bash
./benchmark.sh full
```
Tests all collectives with all sizes. Takes several hours.

### Advanced Usage
```bash
# Direct script usage for fine control
./run_nccl_benchmark.sh -c broadcast -s 1M -m native
./run_nccl_benchmark.sh -c all_reduce -s 4M
./run_nccl_benchmark.sh  # Run everything
```

## Available Collective Operations

- `alltoall` - All-to-all communication
- `gather` - Gather operation  
- `hypercube` - Hypercube algorithm
- `sendrecv` - Send/receive operations
- `all_gather` - All-gather operation
- `reduce` - Reduction operation
- `reduce_scatter` - Reduce-scatter operation
- `scatter` - Scatter operation
- `all_reduce` - All-reduce operation
- `broadcast` - Broadcast operation

## Available Data Sizes

- Small: 8, 1K, 4K, 16K, 64K
- Medium: 256K, 1M, 4M
- Large: 16M, 48M

*Note: `gather` operation uses smaller sizes (8-64K) due to its requirements*

## Output Structure

Results are saved in timestamped directories:
```
benchmark_results_YYYYMMDD_HHMMSS/
├── nccl_benchmark_summary.csv          # Main results CSV
├── benchmark_summary_report.txt        # Human-readable summary  
├── benchmark.log                       # Execution log
├── *_emulated.log                      # Individual test logs
├── *_native.log                        # Individual test logs
├── nccl_*_profile_*.json              # Raw profiling data
└── parse_*.csv                         # Parsed profiling data
```

## CSV Results Format

The main results file `nccl_benchmark_summary.csv` contains:
```
collective,size,mode,avg_kernel_duration_ms,profile_count,test_duration_s
broadcast,1M,emulated,0.123,2,45
broadcast,1M,native,0.089,2,32
...
```

## Configuration

Edit `benchmark_config.sh` to customize:
- Which collectives to test
- Which data sizes to test  
- Test timeout settings
- Output options

## Troubleshooting

### Common Issues

1. **"bc calculator not found"**
   ```bash
   sudo apt-get install bc
   ```

2. **"build directory not found"**
   ```bash
   make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi -B -j
   ```

3. **Tests timeout**
   - Increase `MAX_TEST_DURATION` in `benchmark_config.sh`
   - Check if NEX services are running properly

4. **No profiling data found**
   - Ensure NCCL profiler is properly configured in `run.mk`
   - Check that `NCCL_PROFILE_EVENT_MASK` is set correctly

### Debug Mode

For debugging individual tests:
```bash
# Run with verbose output
make -f run.mk run 2>&1 | tee debug.log

# Check what profile files are generated
ls -la *profile*.json
```

## Performance Analysis

The benchmark provides several metrics:

1. **Kernel Duration**: Average GPU kernel execution time in milliseconds
2. **Profile Count**: Number of profiling samples collected
3. **Test Duration**: Total time for the test execution

### Interpreting Results

- **Lower kernel duration** = Better performance
- **Consistent results** across multiple profiles indicate stable performance
- **Emulated vs Native ratio** shows emulation overhead

### Example Analysis

```bash
# After running benchmarks, analyze results:
python3 -c "
import pandas as pd
df = pd.read_csv('benchmark_results_*/nccl_benchmark_summary.csv')
print(df.groupby(['collective', 'mode'])['avg_kernel_duration_ms'].mean())
"
```

## Integration

The benchmark suite can be integrated into CI/CD pipelines:

```bash
# Return exit code 0 only if all tests pass
./benchmark.sh quick && echo "Benchmarks passed" || echo "Benchmarks failed"

# Generate JSON results for automated processing
python3 -c "
import pandas as pd
df = pd.read_csv('benchmark_results_*/nccl_benchmark_summary.csv')
print(df.to_json(orient='records'))
" > results.json
```

## Contributing

To add new collective operations:
1. Add the executable to `COLLECTIVES` array in `run_nccl_benchmark.sh`
2. Update the configuration in `benchmark_config.sh`
3. Test with a single run first: `./benchmark.sh single -c new_collective -s 1M`
