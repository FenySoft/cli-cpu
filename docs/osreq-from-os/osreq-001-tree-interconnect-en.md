# OSREQ-001: Tree-structured interconnect between cores

> **Source:** [FenySoft/NeuronOS — osreq-001](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-001-tree-interconnect-en.md)
>
> **Status:** Draft — awaiting hardware feedback
>
> **Affected CFPU phase:** F4 (multi-core FPGA), F5 (heterogeneous), F6 (silicon)

## OS-side requirement

Three fundamental Neuron OS structures assume a **tree hierarchy**:

1. **Supervisor tree** — parent-child actor hierarchy (error handling, lifecycle)
2. **Capability delegation** — rights delegate downward from the root supervisor
3. **Memory model** — no shared memory, every core has private SRAM → "sharing" is via mailbox messages that traverse **up and down the tree**

The interconnect topology must reflect this.

## Current state in architecture docs

The `architecture-hu.md` currently states:

> *"At F4 level, a 4-port cross-connection, not yet a crossbar, just a simple mux bundle"*
>
> *"Above 16 cores, the bus topology should become a mesh (2D grid)"*

The **mesh (2D grid)** proposal does not match Neuron OS requirements. The OS supervisor tree is a **tree**, not a grid. Mesh assumes uniform routing, but CFPU communication is **local and hierarchical** (neighboring cores, parent-child supervisor, intra-cluster spikes).

## Proposed topology: Hierarchical tree (fat tree)

```
                         Chip
                          │
                   ┌──────┴──────┐
              Seal Core     Rich Core(s)        Level 0: privileged
                              │
               ┌──────────────┼──────────────┐
           Cluster 0      Cluster 1      Cluster K    Level 1: Nano clusters
            /  |  \        /  |  \        /  |  \
          N0  N1  N2     N3  N4  N5     N6  N7  N8   Level 2: Nano cores
          │   │   │      │   │   │      │   │   │
         4KB 4KB 4KB    4KB 4KB 4KB    4KB 4KB 4KB   Level 3: private SRAM
```

### Routing levels

| Level | Path | Hops | Estimated latency |
|-------|------|------|-------------------|
| Intra-cluster | N→N same cluster | 1 | ~2-4 cycles |
| Inter-cluster | N→N different cluster | 2 | ~6-10 cycles |
| N↔Rich | Supervisor communication | 1-2 | ~4-8 cycles |
| Inter-chip | Chip→Chip | 3+ | ~50-200 cycles |

### Hierarchical addressing

```
Destination: [chip-id].[cluster-id].[core-offset]

Routing decision (O(1), not O(N)):
  if chip-id ≠ own → inter-chip bridge
  if cluster-id ≠ own → chip router → target cluster router
  if cluster-id = own → cluster router (local delivery)
```

### Proposed MMIO registers

| Address | Name | R/W | Description |
|---------|------|-----|-------------|
| `0xF0000108` | `CLUSTER_COUNT` | R/O | Number of clusters |
| `0xF000010C` | `CORES_PER_CLUSTER` | R/O | Cores per cluster |
| `0xF0000110` | `CLUSTER_ID` | R/O | Which cluster this core belongs to |
| `0xF0000114` | `CHIP_ID` | R/O | Multi-chip: which chip |

## Why tree and not mesh?

| Aspect | Mesh (2D grid) | Tree (fat tree) |
|--------|----------------|-----------------|
| **SW alignment** | Does not match supervisor tree | Natural match |
| **Wiring** | O(N) per core (4 neighbors) | O(log N) aggregate |
| **Routing** | XY routing, O(1) but uniform | Hierarchical, O(1) and locality-aware |
| **Communication pattern** | Uniform — not true for CFPU | Local + hierarchical — exactly what supervisor tree does |
| **Scaling to 10k+ cores** | Possible but wasteful | Natural — adding a cluster is O(1) |
| **Broadcast (supervisor restart)** | Flood-based, slow | Tree-broadcast, efficient |

## Open questions for HW designers

1. **Cluster size** — how many Nano cores per cluster? (4? 8? 16?)
2. **Fat tree width** — how wide should the bus be toward the root (chip router)?
3. **Rich Core position** — at tree root (all messages pass through?) or beside it (dedicated uplink)?
4. **Inter-chip link** — SPI? LVDS? Pin count? Max message size?
5. **Cluster router** — programmable or fixed logic?
6. **Broadcast/multicast** — HW multicast support for supervisor restart?

## Impact on architecture docs

The "Scaling to F6" section needs updating: **fat tree** topology instead of **mesh**. This does not change individual core internals (pipeline, decoder, SRAM), only the interconnect structure.

## Cross-references

- Neuron OS source: [osreq-001-tree-interconnect-en.md](https://github.com/FenySoft/NeuronOS/blob/main/docs/osreq-to-cfpu/osreq-001-tree-interconnect-en.md)
- CLI-CPU architecture: `docs/architecture-hu.md` — "Scaling to F6" section
- Neuron OS boot sequence: `docs/boot-sequence-hu.md` — step 8 (Nano Core Wake)
- Neuron OS roadmap: M2.3 (Router), M2.4 (Memory Manager)
