#!/bin/bash
# Unlock all NVIDIA GPUs (restore default clock management)

echo "🔓 Unlocking GPU frequencies..."
echo "   Restoring automatic frequency management"
echo

for id in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
    echo "Unlocking GPU $id..."
    
    # Reset graphics clock to default
    if sudo nvidia-smi -i $id -rgc; then
        echo "✓ GPU $id graphics clock unlocked"
    else
        echo "✗ Failed to unlock graphics clock for GPU $id"
    fi
    
    # Reset memory clock to default
    if sudo nvidia-smi -i $id -rmc; then
        echo "✓ GPU $id memory clock unlocked"
    else
        echo "✗ Failed to unlock memory clock for GPU $id"  
    fi
    echo
done

echo "🎯 GPU frequency unlocking completed"
echo "   GPUs will now use automatic frequency management"