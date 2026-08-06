# Async FIFO — SystemVerilog Implementation

A parameterized asynchronous FIFO (First-In First-Out) buffer implemented in SystemVerilog, designed for safe data transfer between two independent clock domains.

---

## 1. Overview

### Purpose
An async FIFO solves a fundamental problem in digital design: how do you safely pass data between two systems running on completely independent, unrelated clocks? Different frequencies, different phases, no fixed timing relationship between them.

Without a proper synchronization mechanism, data crossing between two clock domains can be captured at the wrong moment, producing corrupted values that never existed in the source domain — a condition called metastability.

The async FIFO solves this by:
- Buffering data in a shared memory array
- Letting the write side push data at its own clock rate
- Letting the read side pull data at its own clock rate
- Using gray code pointers and 2-flop synchronizers to safely communicate pointer positions across the clock domain boundary

### When to use async vs sync FIFO
| | Sync FIFO | Async FIFO |
|---|---|---|
| Clock domains | Single clock | Two independent clocks |
| Use case | Rate buffering in one domain | Clock domain crossing |
| Pointer sync needed | No | Yes — gray code + 2-flop sync |

### Parameters
| Parameter | Default | Description |
|---|---|---|
| `FIFO_DEPTH` | 8 | Number of entries (must be power of 2) |
| `DATA_WIDTH` | 32 | Width of each data entry in bits |

### Ports
| Port | Direction | Description |
|---|---|---|
| `wr_clk` | input | Write domain clock |
| `wr_rst` | input | Write domain reset (active-low async) |
| `wr_en` | input | Write enable |
| `wr_data` | input | Data to write |
| `full` | output | FIFO is full — do not write |
| `rd_clk` | input | Read domain clock |
| `rd_rst` | input | Read domain reset (active-low async) |
| `rd_en` | input | Read enable |
| `rd_data` | output | Data read out (combinational) |
| `empty` | output | FIFO is empty — do not read |

---

## 2. Architecture and Datapath

The design is split cleanly into two independent clock domains with a shared memory array between them.
![FIFO Architecture](async_fifo_design.pdf)

### Key design decision — data never crosses the clock boundary

The shared memory array is written by the write domain and read by the read domain, but the data itself never crosses any synchronizer. Only the **pointers** cross — as single-bit-change gray code values through 2-flop synchronizers. The data just sits in the memory array, stable, until the read side is ready.

### Module hierarchy
```
async_fifo (top)
├── memory array (shared)
├── write pointer logic (wr_clk domain)
├── read pointer logic (rd_clk domain)
├── binary → gray conversion (combinational)
├── wq sync: wr_ptr_gray → rd_clk domain (2-flop)
├── rq sync: rd_ptr_gray → wr_clk domain (2-flop)
├── empty flag (rd_clk domain)
└── full flag (wr_clk domain)
```

---

## 3. Gray Code

### The problem with binary pointers across clock domains

When a binary counter increments from 3 to 4, multiple bits change simultaneously:

```
3 = 0 1 1
4 = 1 0 0  ← all three bits change at once
```

A 2-flop synchronizer samples bits independently. If it catches the pointer mid-transition, some bits capture the old value and some capture the new value — producing a corrupt intermediate value like `110` = 6 that never actually existed. This causes the full or empty flag to fire incorrectly.

### Why gray code fixes this

Gray code is an encoding where **only one bit changes per increment**:

```
decimal │ binary │ gray
────────┼────────┼──────
   0    │  0000  │ 0000
   1    │  0001  │ 0001
   2    │  0010  │ 0011
   3    │  0011  │ 0010
   4    │  0100  │ 0110  ← only 1 bit changed from previous
   5    │  0101  │ 0111
   6    │  0110  │ 0101
   7    │  0111  │ 0100
   8    │  1000  │ 1100
```

When the synchronizer samples a gray code pointer mid-transition, only one bit is ever in-flight. You either capture the old value or the new value — never a corrupted combination of bits from two different points in time.

### Implementation — binary to gray conversion

One line, purely combinational:

```systemverilog
assign write_gray_pointer = write_pointer ^ (write_pointer >> 1);
assign read_gray_pointer  = read_pointer  ^ (read_pointer  >> 1);
```

XOR the binary value with itself shifted right by 1. No clock needed — updates instantly whenever the binary pointer changes.

---

## 4. Synchronizers

### Why synchronizers are needed

After converting to gray code, the pointers still need to cross the clock domain boundary. A signal changing in one clock domain and sampled by a flip-flop in another domain can violate setup or hold time, sending that flip-flop into a metastable state — output neither a clean 0 nor a clean 1 for an unpredictable amount of time.

### Why two flops and not one

A single flip-flop gives zero recovery time — the potentially metastable output is passed straight to logic.

A two-flop synchronizer gives the first flip-flop a **full clock cycle to resolve** before the second flip-flop samples it:

```
gray pointer ──→ [ DFF 1 ] ──→ [ DFF 2 ] ──→ safe synchronized value
(async)          may be         settled,
                 metastable     stable output
                 ↑                   ↑
              clk_dst             clk_dst
```

By the time DFF 2 samples DFF 1's output, metastability has almost certainly resolved. DFF 2 then passes a clean, stable value to the full/empty comparison logic.

### Two synchronizers — one per direction

```systemverilog
// wr_ptr_gray crossing into read domain → used for EMPTY detection
always_ff @(posedge rd_clk or negedge rd_rst) begin
    if (!rd_rst) begin
        wq1_rptr <= 0;
        wq2_rptr <= 0;  // wq2_rptr is the safe synchronized output
    end else begin
        wq1_rptr <= write_gray_pointer;
        wq2_rptr <= wq1_rptr;
    end
end

// rd_ptr_gray crossing into write domain → used for FULL detection
always_ff @(posedge wr_clk or negedge wr_rst) begin
    if (!wr_rst) begin
        rq1_wptr <= 0;
        rq2_wptr <= 0;  // rq2_wptr is the safe synchronized output
    end else begin
        rq1_wptr <= read_gray_pointer;
        rq2_wptr <= rq1_wptr;
    end
end
```

Naming convention: `wq2_rptr` = write pointer, 2nd flop, in read domain. `rq2_wptr` = read pointer, 2nd flop, in write domain.

---

## 5. Full and Empty Conditions

### Empty — detected in the read domain

```systemverilog
assign empty = (wq2_rptr == read_gray_pointer);
```

Empty when the synchronized write pointer equals the local read pointer in gray code. Both pointers are at the same position — nothing to read.

Both signals live in the read clock domain so this comparison is safe — `wq2_rptr` is the synchronized write pointer, `read_gray_pointer` is local to the read domain.

### Full — detected in the write domain

Full is trickier. When the write pointer has lapped the read pointer exactly once, the top TWO gray code bits differ between the pointers while the remaining bits match.

```systemverilog
assign full = (write_gray_pointer[FIFO_DEPTH_LOG]     != rq2_wptr[FIFO_DEPTH_LOG])   &&
              (write_gray_pointer[FIFO_DEPTH_LOG-1]   != rq2_wptr[FIFO_DEPTH_LOG-1]) &&
              (write_gray_pointer[FIFO_DEPTH_LOG-2:0] == rq2_wptr[FIFO_DEPTH_LOG-2:0]);
```

### Why the top TWO bits for full (not one)

In binary, full means the top bit differs and the lower bits match. But in gray code, the transition at the exact halfway point causes two bits to flip simultaneously:

```
binary 0111 → gray 0100
binary 1000 → gray 1100  ← bits 3 AND 2 both flipped
```

So at the full condition, the write gray pointer has `11` in the top two bits while the synchronized read pointer still has `00` — both top bits differ. Checking only the MSB would miss this.

### Overflow and underflow protection

The write pointer only increments when `wr_en && !full` — writes are silently dropped when the FIFO is full, preventing overflow.

The read pointer only increments when `rd_en && !empty` — reads are blocked when the FIFO is empty, preventing underflow.

`rd_data` is combinational and always reflects `mem[rd_ptr]` — the empty flag is the signal that tells the consumer whether the data on `rd_data` is actually valid.

---

## Verification

Testbench covers:
- Reset state — empty asserted, full deasserted
- Write and read in FIFO order — data comes out in the same order it went in
- Full flag assertion after writing DEPTH items
- Overflow protection — writes ignored when full
- Empty flag assertion after draining completely
- Simultaneous read and write
- Continuous SVA assertion: `full && empty` can never both be true

---
## Synthesis and Implementation

Synthesis and Implementation was run to target the AC701 Artix-7 FPGA on Vivado. When it ran, 91 LUTs and 280 FFs were used. There are 256 FFs used just for memory, so around 24 FF come from BRAM. It runs at 244 MHz. 

---
## References

- Clifford Cummings — "Simulation and Synthesis Techniques for Asynchronous FIFO Design" (sunburst-design.com) — the industry standard reference for this design pattern
- Patterson & Hennessy — Computer Organization and Design

