#!/bin/bash
# Lock GPU frequencies for consistent benchmarking
# Set these to your desired values (must be supported by your GPU)
GRAPHICS_CLOCK=1530  # Maximum supported graphics frequency
MEM_CLOCK=877        # Maximum supported memory frequency

echo "Lock CPU frequencies to max for stable benchmarking..."
# sudo cpupower frequency-set -g performance >/dev/null 2>&1 || true
# echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
echo "🔒 Locking GPU frequencies for stable benchmarking..."
echo "   Graphics Clock: $GRAPHICS_CLOCK MHz"
echo "   Memory Clock: $MEM_CLOCK MHz"
echo

for id in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
    echo "Setting GPU $id to graphics: $GRAPHICS_CLOCK MHz, memory: $MEM_CLOCK MHz"
    
    # Lock graphics clock to specific frequency
    if sudo nvidia-smi -i $id -lgc $GRAPHICS_CLOCK,$GRAPHICS_CLOCK; then
        echo "✓ GPU $id graphics clock locked to $GRAPHICS_CLOCK MHz"
    else
        echo "✗ Failed to lock graphics clock for GPU $id"
    fi
    
    # Lock memory clock
    if sudo nvidia-smi -i $id -lmc $MEM_CLOCK; then
        echo "✓ GPU $id memory clock locked to $MEM_CLOCK MHz"
    else
        echo "✗ Failed to lock memory clock for GPU $id"
    fi
    echo
done

echo "🎯 GPU frequency locking completed"
echo "   Use unlock_freq.sh to restore automatic frequency management"