#!/bin/bash

#  make MPI=1  MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi -B -j
# make MPI=1 MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi -B -j

PRELOAD_LIB="/home/jma/NEX/src/sims/gpu/nex_cuda.so"
PROJECT_DIR := "/home/jma/NEX"

# failed

#success:
# TARGET_MPI_ONE=./build/alltoall_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/gather_perf -b 8 -e 8 -g 1
# TARGET_MPI_ONE=./build/hypercube_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/sendrecv_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/all_gather_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/reduce_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/reduce_scatter_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/scatter_perf -b 1M -e 1M -g 1
# TARGET_MPI_ONE=./build/all_reduce_perf -b 1M -e 1M -g 1
TARGET_MPI_ONE=./build/broadcast_perf -b 16K -e 16K -g 1

# TARGET_MPI_ONE=ifconfig

# TARGET_MPI_ONE := $(PWD)/build/all_reduce_perf -b 8 -e 1M -f 2 -g 1

#   LD_PRELOAD=${PRELOAD_LIB} \
#   REPLACE_LIB=${PRELOAD_LIB} \
#   LD_PRELOAD=$(PROJECT_DIR)/nccl/ext-profiler/example/libnccl-profiler.so \
LD_PRELOAD=$(PROJECT_DIR)/nccl/ext-profiler/example/libnccl-profiler.so \
  NCCL_PROFILE_EVENT_MASK=255 \
  LD_PRELOAD=$(PROJECT_DIR)/src/sims/gpu/nex_cuda.so \
  REPLACE_LIB=$(PROJECT_DIR)/src/sims/gpu/nex_cuda.so \

#   LD_PRELOAD=$(PROJECT_DIR)/nccl/ext-profiler/example/libnccl-profiler.so \
  LD_PRELOAD=$(PROJECT_DIR)/src/sims/gpu/nex_cuda.so \
  REPLACE_LIB=$(PROJECT_DIR)/src/sims/gpu/nex_cuda.so \

MPI_ENV := \
  LD_PRELOAD=$(PROJECT_DIR)/nccl/ext-profiler/example/libnccl-profiler.so:$(PROJECT_DIR)/src/sims/gpu/nex_cuda.so \
  REPLACE_LIB=$(PROJECT_DIR)/src/sims/gpu/nex_cuda.so\
  NCCL_PROFILE_EVENT_MASK=64 \
  LD_LIBRARY_PATH="$(PROJECT_DIR)/nccl/build/lib" \
  NCCL_DEBUG=ERROR NCCL_DEBUG_SUBSYS=ALL NCCL_CROSS_NIC=1 \
  NCCL_TOPO_FILE=$(CURDIR)/topo_tap_nccl.xml NCCL_OOB_NET_ENABLE=0 \
  NCCL_P2P_DISABLE=1 NCCL_CUMEM_ENABLE=0 NCCL_CUMEM_HOST_ENABLE=1 \
  NCCL_P2P_LEVEL=LOC NCCL_COLLNET_ENABLE=0 NCCL_P2P_DIRECT_DISABLE=1 \
  NCCL_MAX_NCHANNELS=1 NCCL_IB_DISABLE=1 NCCL_SHM_DISABLE=1 NCCL_NVLS_ENABLE=0 \
  NCCL_NUM_MOCK_GPU=2 NCCL_NUM_MOCK_NODE=2 NCCL_NET_SHARED_BUFFERS=0 \
  NCCL_RAS_ENABLE=0 NCCL_NET="Socket" NCCL_PROTO="Simple"

# run under gdb
COMMAND := 'PORT=$$((12340 + $$OMPI_COMM_WORLD_RANK)); \
            echo "Rank $$OMPI_COMM_WORLD_RANK listening on port $$PORT"; \
            exec gdbserver :$$PORT ./$(TARGET_MPI_ONE)'

COMMAND1 := "NEX_ID=0 taskset -c 0-10 ./$(TARGET_MPI_ONE)"
COMMAND2 := "NEX_ID=1 taskset -c 11-21 ./$(TARGET_MPI_ONE)"

# COMMAND1 := 'PORT=$$((12340 + $$OMPI_COMM_WORLD_RANK)); NEX_ID=0; \
#             echo "Rank $$OMPI_COMM_WORLD_RANK listening on port $$PORT"; \
#             exec gdbserver :$$PORT ./$(TARGET_MPI_ONE)'

# COMMAND2 := 'PORT=$$((12340 + $$OMPI_COMM_WORLD_RANK)); NEX_ID=1; \
#             echo "Rank $$OMPI_COMM_WORLD_RANK listening on port $$PORT"; \
#             exec gdbserver :$$PORT ./$(TARGET_MPI_ONE)'
run:
	@echo "Running MPI OneDevicePerProcess test"
	@echo "Output will be written to mpi-one-rank-*.out files"
	$(MPI_ENV) \
	mpirun --hostfile hosts --output-filename mpi-one-rank \
	-np 1 \
	-x NCCL_PROFILE_EVENT_MASK \
	-x NCCL_CUMEM_ENABLE \
	-x NCCL_CUMEM_HOST_ENABLE \
		-x LD_LIBRARY_PATH \
		-x LD_PRELOAD \
		-x REPLACE_LIB \
		-x NCCL_DEBUG \
		-x NCCL_DEBUG_SUBSYS \
		-x NCCL_CROSS_NIC \
		-x NCCL_TOPO_FILE \
		-x NCCL_OOB_NET_ENABLE \
		-x NCCL_P2P_DISABLE \
		-x NCCL_P2P_LEVEL \
		-x NCCL_COLLNET_ENABLE \
		-x NCCL_P2P_DIRECT_DISABLE \
		-x NCCL_MAX_NCHANNELS \
		-x NCCL_IB_DISABLE \
		-x NCCL_SHM_DISABLE \
		-x NCCL_NVLS_ENABLE \
		-x NCCL_NUM_MOCK_GPU \
		-x NCCL_NUM_MOCK_NODE \
		-x NCCL_NET_SHARED_BUFFERS \
		-x NCCL_RAS_ENABLE \
		-x NCCL_NET \
		-x NCCL_PROTO \
	   -x NCCL_SOCKET_IFNAME=tap-nccl-0 \
	   -x NCCL_HOSTID="rs3labsrv865d3961f-75cc-426b-8e7b-3ac85d495be0" \
	   -x NCCL_TOPO_DUMP_FILE=$(CURDIR)/topo_dump_mpi0.xml \
	   -x NCCL_PROFILE_DUMP_FILE=$(CURDIR)/nccl_profile_rank0 \
	   bash -c $(COMMAND1) \
	: \
	-np 1 \
		-x NCCL_PROFILE_EVENT_MASK \
		-x NCCL_CUMEM_ENABLE \
		-x NCCL_CUMEM_HOST_ENABLE \
		-x LD_LIBRARY_PATH \
		-x LD_PRELOAD \
		-x REPLACE_LIB \
		-x NCCL_DEBUG \
		-x NCCL_DEBUG_SUBSYS \
		-x NCCL_CROSS_NIC \
		-x NCCL_TOPO_FILE \
		-x NCCL_OOB_NET_ENABLE \
		-x NCCL_P2P_DISABLE \
		-x NCCL_P2P_LEVEL \
		-x NCCL_COLLNET_ENABLE \
		-x NCCL_P2P_DIRECT_DISABLE \
		-x NCCL_MAX_NCHANNELS \
		-x NCCL_IB_DISABLE \
		-x NCCL_SHM_DISABLE \
		-x NCCL_NVLS_ENABLE \
		-x NCCL_NUM_MOCK_GPU \
		-x NCCL_NUM_MOCK_NODE \
		-x NCCL_NET_SHARED_BUFFERS \
		-x NCCL_RAS_ENABLE \
		-x NCCL_NET \
		-x NCCL_PROTO \
	   -x NCCL_SOCKET_IFNAME=tap-nccl-1 \
	   -x NCCL_HOSTID="rs3labsrv831b7e60e-183d-4d26-af0a-fd9a29591648" \
	   -x NCCL_TOPO_DUMP_FILE=$(CURDIR)/topo_dump_mpi1.xml \
		-x NCCL_PROFILE_DUMP_FILE=$(CURDIR)/nccl_profile_rank1 \
		bash -c $(COMMAND2) \



MPI_ENV_NATIVE := \
  LD_LIBRARY_PATH="/home/jma/nccl/build/lib" \
  LD_PRELOAD=/home/jma/nccl/ext-profiler/example/libnccl-profiler.so \
  NCCL_PROFILE_EVENT_MASK=64 \
  NCCL_DEBUG=ERROR NCCL_DEBUG_SUBSYS=ALL NCCL_CROSS_NIC=1 \
  NCCL_OOB_NET_ENABLE=0 \
  NCCL_P2P_DISABLE=1 NCCL_CUMEM_ENABLE=0 NCCL_CUMEM_HOST_ENABLE=1 \
  NCCL_P2P_LEVEL=LOC NCCL_COLLNET_ENABLE=0 NCCL_P2P_DIRECT_DISABLE=1 \
  NCCL_MAX_NCHANNELS=1 NCCL_IB_DISABLE=1 NCCL_SHM_DISABLE=1 NCCL_NVLS_ENABLE=0 \
  NCCL_NUM_MOCK_GPU=2 NCCL_NUM_MOCK_NODE=2 NCCL_NET_SHARED_BUFFERS=0 \
  NCCL_RAS_ENABLE=0 NCCL_NET="Socket" NCCL_PROTO="Simple"

# run under gdb
# COMMAND := 'PORT=$$((12340 + $$OMPI_COMM_WORLD_RANK)); \
            echo "Rank $$OMPI_COMM_WORLD_RANK listening on port $$PORT"; \
            exec gdbserver :$$PORT ./$(TARGET_MPI_ONE)'

# COMMAND1_NATIVE := "nsys profile --trace=cuda ./$(TARGET_MPI_ONE)"
# COMMAND2_NATIVE := "nsys profile --trace=cuda ./$(TARGET_MPI_ONE)"

COMMAND1_NATIVE := "taskset -c 0-10 ./$(TARGET_MPI_ONE)"
COMMAND2_NATIVE := "taskset -c 11-21 ./$(TARGET_MPI_ONE)"

run-native:
	@echo "Running MPI OneDevicePerProcess test"
	@echo "Output will be written to mpi-one-rank-*.out files"
	$(MPI_ENV_NATIVE) \
	mpirun --hostfile hosts --output-filename mpi-one-rank \
	-np 1 \
	-x NCCL_CUMEM_ENABLE \
	-x NCCL_PROFILE_EVENT_MASK \
	-x NCCL_CUMEM_HOST_ENABLE \
		-x LD_LIBRARY_PATH \
		-x LD_PRELOAD \
		-x NCCL_DEBUG \
		-x NCCL_DEBUG_SUBSYS \
		-x NCCL_CROSS_NIC \
		-x NCCL_TOPO_FILE \
		-x NCCL_OOB_NET_ENABLE \
		-x NCCL_P2P_DISABLE \
		-x NCCL_P2P_LEVEL \
		-x NCCL_COLLNET_ENABLE \
		-x NCCL_P2P_DIRECT_DISABLE \
		-x NCCL_MAX_NCHANNELS \
		-x NCCL_IB_DISABLE \
		-x NCCL_SHM_DISABLE \
		-x NCCL_NVLS_ENABLE \
		-x NCCL_NUM_MOCK_GPU \
		-x NCCL_NUM_MOCK_NODE \
		-x NCCL_NET_SHARED_BUFFERS \
		-x NCCL_RAS_ENABLE \
		-x NCCL_NET \
		-x NCCL_PROTO \
	   -x NCCL_SOCKET_IFNAME=tap-nccl-0 \
	   -x NCCL_PROFILE_DUMP_FILE=$(CURDIR)/nccl_native_profile_r0 \
	   bash -c $(COMMAND1_NATIVE) \
	: \
	-np 1 \
		-x LD_LIBRARY_PATH \
		-x LD_PRELOAD \
		-x NCCL_PROFILE_EVENT_MASK \
		-x NCCL_CUMEM_ENABLE \
		-x NCCL_CUMEM_HOST_ENABLE \
		-x NCCL_DEBUG \
		-x NCCL_DEBUG_SUBSYS \
		-x NCCL_CROSS_NIC \
		-x NCCL_TOPO_FILE \
		-x NCCL_OOB_NET_ENABLE \
		-x NCCL_P2P_DISABLE \
		-x NCCL_P2P_LEVEL \
		-x NCCL_COLLNET_ENABLE \
		-x NCCL_P2P_DIRECT_DISABLE \
		-x NCCL_MAX_NCHANNELS \
		-x NCCL_IB_DISABLE \
		-x NCCL_SHM_DISABLE \
		-x NCCL_NVLS_ENABLE \
		-x NCCL_NUM_MOCK_GPU \
		-x NCCL_NUM_MOCK_NODE \
		-x NCCL_NET_SHARED_BUFFERS \
		-x NCCL_RAS_ENABLE \
		-x NCCL_NET \
		-x NCCL_PROTO \
	   -x NCCL_SOCKET_IFNAME=tap-nccl-1 \
	   -x NCCL_PROFILE_DUMP_FILE=$(CURDIR)/nccl_native_profile_r1 \
		bash -c $(COMMAND2_NATIVE) \


# Collective test starting: broadcast_perf
# nThread 1 nGpus 1 minBytes 1048576 maxBytes 1048576 step: 1048576(bytes) warmup iters: 1 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid 698561 on ecocloud-exp06 device  0 [0000:18:00] Tesla V100-SXM2-32GB
#  Rank  1 Group  0 Pid 698562 on ecocloud-exp06 device  1 [0000:3b:00] Tesla V100-SXM2-32GB
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
#     1048576        262144     float    none       0    461.9    2.27    2.27      0    401.4    2.61    2.61      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 2.4413 
#
# Collective test concluded: broadcast_perf