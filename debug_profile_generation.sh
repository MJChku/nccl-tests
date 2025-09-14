#!/bin/bash

# Debug script to see what profile files are generated

cd /home/jma/NEX/tests/nccl-tests

echo "=== Before test ==="
ls -la nccl_*profile*.json kernel_profile*.json 2>/dev/null || echo "No profile files"

echo "=== Running emulated test ==="
timeout 30 make -f run.mk run > debug_emulated.log 2>&1 || true

echo "=== After emulated test ==="
ls -la nccl_*profile*.json kernel_profile*.json 2>/dev/null || echo "No profile files"

echo "=== Generated files details ==="
find . -name "*.json" -newer run.mk 2>/dev/null | head -10

echo "=== Debug log tail ==="
tail -20 debug_emulated.log
