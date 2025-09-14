#!/bin/bash

# NCCL Test Automation Script
# Runs performance tests for various operations and configurations
# Supports single-machine and two-machine (MPI) cases

# Configurable parameters
OPERATIONS=(all_reduce reduce broadcast all_gather alltoall reduce_scatter gather scatter sendrecv hypercube)
GPUS=(1 2 3 4)
LOGDIR=logs_new
SUMMARY=summary.csv
HOSTFILE=hostfile

mkdir -p "$LOGDIR"
# Update CSV header to include all columns
echo "operation,mode,gpus,size,count,type,redop,root,oop_time,oop_algbw,oop_busbw,oop_wrong,ip_time,ip_algbw,ip_busbw,ip_wrong,logfile" > "$SUMMARY"

# Helper to extract all columns from the last numeric line
extract_perf() {
    local logfile=$1
    # Get the last numeric line (largest message size)
    local perf_line=$(awk '/^[[:space:]]*[0-9]+/ {line=$0} END{print line}' "$logfile")
    # Replace multiple spaces with a single space, then convert to CSV
    local csv_line=$(echo "$perf_line" | sed 's/  */ /g' | sed 's/^ //;s/ $//' | tr ' ' ',')
    echo "$csv_line"
}

for op in "${OPERATIONS[@]}"; do
  BIN=build/${op}_perf

  # Copy binary to /tmp on local and remote machines
  cp "$BIN" /tmp/
  if [[ "$host" != "localhost" && "$host" != "$local_short_host" ]]; then
    scp "$BIN" "$host:/tmp/"
  fi

  for g in "${GPUS[@]}"; do
    if [ ! -x "$BIN" ]; then continue; fi
    LOG="$LOGDIR/${op}_mpi_${g}g.log"  
    
    echo "Running mpirun --hostfile $HOSTFILE /tmp/${op}_perf -g $g (two machine) ..."
    mpirun --prefix /home/xingzhan/opt/openmpi --hostfile $HOSTFILE -np 2 --map-by node -x LD_LIBRARY_PATH=/home/xingzhan/opt/openmpi/lib -x LD_PRELOAD=/home/xingzhan/nex-cricket/nccl/ext-net/example/libnccl-net.so:/home/xingzhan/nex-cricket/nccl/ext-profiler/example/libnccl-profiler.so:/home/xingzhan/nex-cricket/nccl/ext-tuner/example/libnccl-tuner.so -x NCCL_DEBUG=INFO -x NCCL_PROFILE_DUMP_FILE="$LOGDIR/${op}_mpi_${g}g" -x NCCL_PROFILE_EVENT_MASK=255 /tmp/${op}_perf -g $g > "$LOG" 2>&1
    perf=$(extract_perf "$LOG")
    echo "$op,profiler,$g,$perf,$LOG" >> "$SUMMARY"

    LOG="$LOGDIR/${op}_mpi_${g}g_noprofiler.log"  
    mpirun --prefix /home/xingzhan/opt/openmpi --hostfile $HOSTFILE -np 2 --map-by node -x LD_LIBRARY_PATH=/home/xingzhan/opt/openmpi/lib /tmp/${op}_perf -g $g > "$LOG" 2>&1
    perf=$(extract_perf "$LOG")
    echo "$op,noprofiler,$g,$perf,$LOG" >> "$SUMMARY"
  done
done

# make -f run.mk run 
LOG="nccl_profile_rank1_439542058859542123_1.json"  
perf=$(extract_perf "$LOG")
# echo "$op,noprofiler,$g,$perf,$LOG" >> "$SUMMARY"
echo "$perf" >> "$SUMMARY"
echo "\nSummary written to $SUMMARY."
cat "$SUMMARY"

# /home/xingzhan/nex-cricket/nccl/build/lib/libnccl.so:
# -x NCCL_PROFILE_DUMP_FILE="$LOGDIR/${op}_mpi_${g}g"