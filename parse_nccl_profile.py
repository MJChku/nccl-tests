#!/usr/bin/env python3
"""
NCCL Profile Parser

P    def    def __str__(self):
        return (f"{self.collective.name} "
                f"(Count={self.collective.count}, "
                f"Dat    # Sort both lists by ID for direct matching
    collectives_sorted = sorted(collectives, key=lambda x: x.id)
    kernels_sorted = sorted(kernels, key=lambda x: x.id)
    
    # Since kernels and collectives are both sorted by ID, we can match them directly
    # Each kernel corresponds to the collective with the same index
    for i, kernel in enumerate(kernels_sorted):
        if i < len(collectives_sorted):
            collective = collectives_sorted[i]
            associations.append(AssociatedKernel(kernel, collective))f.collective.datatype}, "
                f"Algo={self.collective.algorithm}, "
                f"Proto={self.collective.protocol}) "
                f"-> KernelCh[{self.kernel.channel}] "
                f"Duration={self.kernel.duration_ms:.3f}ms")self):
        return (f"{self.collective.name} "
                f"(Count={self.collective.count}, "
                f"Datatype={self.collective.datatype}, "
                f"Algo={self.collective.algorithm}, "
                f"Proto={self.collective.protocol}) "
                f"-> KernelCh[{self.kernel.channel}] "
                f"Duration={self.kernel.duration_ms:.3f}ms "
                f"GPU_Clks={self.kernel.gpu_duration_clks}")L profiling JSON files to extract and associate KernelCh timing data
with collective operation metadata (operation type, count, datatype, algorithm, protocol).
"""

import json
import sys
import argparse
from typing import List, Dict, Any, Optional
from dataclasses import dataclass
from collections import defaultdict


@dataclass
class KernelChEvent:
    """Represents a KernelCh GPU execution event"""
    id: int
    channel: int
    duration_ms: float


@dataclass
class CollectiveEvent:
    """Represents a collective operation (Broadcast, AllReduce, etc.)"""
    id: int
    name: str
    seq_num: int
    comm_hash: int
    rank: int
    count: int
    datatype: str
    algorithm: str
    protocol: str
    n_channels: int
    start_ts: float
    end_ts: float
    duration_us: float


@dataclass
class AssociatedKernel:
    """KernelCh event associated with collective metadata"""
    kernel: KernelChEvent
    collective: CollectiveEvent
    
    def __str__(self):
        return (f"{self.collective.name} "
                f"(Count={self.collective.count}, "
                f"Datatype={self.collective.datatype}, "
                f"Algo={self.collective.algorithm}, "
                f"Proto={self.collective.protocol}) "
                f"-> KernelCh[{self.kernel.channel}] "
                f"Duration={self.kernel.duration_ms:.3f}ms")


def parse_nccl_profile(filename: str) -> List[Dict[str, Any]]:
    """Load and parse NCCL profile JSON file"""
    try:
        with open(filename, 'r') as f:
            data = json.load(f)
        
        # Check if this is a NEX kernel profile (has "pid" and "kernels" fields)
        if isinstance(data, dict) and "pid" in data and "kernels" in data:
            # This is a NEX kernel profile, return the kernels array
            return data["kernels"]
        
        # Otherwise it's an NCCL profile array format
        # Remove the empty object at the end if it exists
        if data and isinstance(data, list) and data[-1] == {}:
            data.pop()
            
        return data
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{filename}': {e}")
        sys.exit(1)


def extract_events(events: List[Dict[str, Any]]) -> tuple[List[CollectiveEvent], List[KernelChEvent]]:
    """Extract collective operations and kernel events from raw event data"""
    collectives = []
    kernels = []
    
    # First pass: collect all collective operations by id
    collective_begins = {}
    collective_ends = {}
    
    for event in events:
        if event.get('cat') == 'COLL':
            event_id = event.get('id')
            if event.get('ph') == 'b':  # begin
                collective_begins[event_id] = event
            elif event.get('ph') == 'e':  # end
                collective_ends[event_id] = event
    
    # Create collective events
    for event_id in collective_begins:
        if event_id in collective_ends:
            begin_event = collective_begins[event_id]
            end_event = collective_ends[event_id]
            args = begin_event.get('args', {})
            
            collective = CollectiveEvent(
                id=event_id,
                name=begin_event.get('name', 'Unknown'),
                seq_num=args.get('SeqNum', 0),
                comm_hash=args.get('CommHash', 0),
                rank=args.get('Rank', 0),
                count=args.get('Count', 0),
                datatype=args.get('Datatype', 'Unknown'),
                algorithm=args.get('Algorithm', 'Unknown'),
                protocol=args.get('Protocol', 'Unknown'),
                n_channels=args.get('nChannels', 0),
                start_ts=begin_event.get('ts', 0),
                end_ts=end_event.get('ts', 0),
                duration_us=end_event.get('ts', 0) - begin_event.get('ts', 0)
            )
            collectives.append(collective)
    
    # Second pass: collect all kernel events by scanning for begin/end pairs
    kernel_begins = []
    kernel_ends = []
    
    for event in events:
        if event.get('cat') == 'GPU' and event.get('name') == 'KernelCh':
            if event.get('ph') == 'b':  # begin
                kernel_begins.append(event)
            elif event.get('ph') == 'e':  # end
                kernel_ends.append(event)
    
    # Sort by timestamp to match begins with ends
    kernel_begins.sort(key=lambda x: x.get('ts', 0))
    kernel_ends.sort(key=lambda x: x.get('ts', 0))
    
    # Match kernel begins with ends based on temporal proximity
    used_ends = set()
    kernel_id_counter = 0
    
    for begin_event in kernel_begins:
        begin_ts = begin_event.get('ts', 0)
        best_end = None
        best_distance = float('inf')
        
        # Find the closest end event that comes after this begin
        for i, end_event in enumerate(kernel_ends):
            if i in used_ends:
                continue
                
            end_ts = end_event.get('ts', 0)
            if end_ts > begin_ts:  # End must come after begin
                distance = end_ts - begin_ts
                if distance < best_distance:
                    best_distance = distance
                    best_end = (i, end_event)
        
        if best_end:
            end_idx, end_event = best_end
            used_ends.add(end_idx)
            
            args = begin_event.get('args', {})
            # Calculate duration in milliseconds from timestamps
            duration_us = end_event.get('ts', 0) - begin_event.get('ts', 0)
            duration_ms = duration_us / 1000.0  # Convert microseconds to milliseconds
            
            kernel = KernelChEvent(
                id=kernel_id_counter,  # Use sequential ID for kernels
                channel=args.get('Channel', 0),
                duration_ms=duration_ms
            )
            kernels.append(kernel)
            kernel_id_counter += 1
    
    return collectives, kernels


def associate_kernels_with_collectives(collectives: List[CollectiveEvent], 
                                     kernels: List[KernelChEvent]) -> List[AssociatedKernel]:
    """Associate kernel events with their corresponding collective operations"""
    associations = []
    
    # Sort both lists by ID for direct matching
    collectives_sorted = sorted(collectives, key=lambda x: x.id)
    kernels_sorted = sorted(kernels, key=lambda x: x.id)
    
    # Since kernels and collectives are both sorted by ID, we can match them directly
    # Each kernel corresponds to the collective with the same index
    for i, kernel in enumerate(kernels_sorted):
        if i < len(collectives_sorted):
            collective = collectives_sorted[i]
            associations.append(AssociatedKernel(kernel, collective))
    
    return associations


def print_summary(associations: List[AssociatedKernel]):
    """Print summary statistics"""
    if not associations:
        print("No kernel-collective associations found!")
        return
    
    print(f"\n=== NCCL Profile Summary ===")
    print(f"Total kernel events: {len(associations)}")
    
    # Group by operation type
    by_operation = defaultdict(list)
    for assoc in associations:
        by_operation[assoc.collective.name].append(assoc)
    
    print(f"Operations: {', '.join(by_operation.keys())}")
    
    # Statistics per operation
    for op_name, op_associations in by_operation.items():
        durations = [a.kernel.duration_ms for a in op_associations]
        
        print(f"\n{op_name} ({len(op_associations)} kernels):")
        print(f"  Duration - Min: {min(durations):.3f}ms, Max: {max(durations):.3f}ms, Avg: {sum(durations)/len(durations):.3f}ms")
        
        # Show first few examples
        print(f"  Examples:")
        for i, assoc in enumerate(op_associations[:3]):
            print(f"    {i+1}. {assoc}")
        if len(op_associations) > 3:
            print(f"    ... and {len(op_associations)-3} more")


def export_csv(associations: List[AssociatedKernel], output_file: str):
    """Export associations to CSV format"""
    import csv
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        
        # Header
        writer.writerow([
            'id', 'operation', 'seq_num', 'rank', 'count', 'datatype', 
            'algorithm', 'protocol', 'n_channels', 'channel', 'duration_ms'
        ])
        
        # Data rows
        for assoc in associations:
            writer.writerow([
                assoc.collective.id,
                assoc.collective.name,
                assoc.collective.seq_num,
                assoc.collective.rank,
                assoc.collective.count,
                assoc.collective.datatype,
                assoc.collective.algorithm,
                assoc.collective.protocol,
                assoc.collective.n_channels,
                assoc.kernel.channel,
                assoc.kernel.duration_ms
            ])
    
    print(f"Exported {len(associations)} associations to {output_file}")


def main():
    parser = argparse.ArgumentParser(description='Parse NCCL profiling data and associate kernels with collectives')
    parser.add_argument('input_file', help='Input NCCL profile JSON file')
    parser.add_argument('--csv', help='Export results to CSV file')
    parser.add_argument('--verbose', '-v', action='store_true', help='Show detailed output for each kernel')
    
    args = parser.parse_args()
    
    # Parse the profile
    print(f"Parsing NCCL profile: {args.input_file}")
    events = parse_nccl_profile(args.input_file)
    print(f"Loaded {len(events)} events")
    
    # Extract and associate events
    collectives, kernels = extract_events(events)
    print(f"Found {len(collectives)} collective operations and {len(kernels)} kernel events")
    
    associations = associate_kernels_with_collectives(collectives, kernels)
    print(f"Successfully associated {len(associations)} kernel-collective pairs")
    
    # Print results
    if args.verbose:
        print(f"\n=== Detailed Results ===")
        for i, assoc in enumerate(associations, 1):
            print(f"{i:2d}. {assoc}")
    
    print_summary(associations)
    
    # Export if requested
    if args.csv:
        export_csv(associations, args.csv)
    
    print("\nDone!")


if __name__ == '__main__':
    main()
