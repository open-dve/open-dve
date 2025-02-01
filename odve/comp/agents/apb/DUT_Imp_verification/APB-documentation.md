# APB Master/Slave Design Documentation

**Prepared by:** Youssef Nasser  
**Role:** Design Verification Engineer  
**Email:** youssefnasserabdelaal@gmail.com  
**Submitted to:** Eng.Viktor

## Table of Contents
- [Introduction to APB](#introduction-to-apb)
- [Specifications](#specifications)
  - [Design Implementation and verification](#design-implementation-and-verification)
  - [APB Master Specifications](#apb-master-specifications)
  - [APB Slave Specifications](#apb-slave-specifications)
- [Interface Signals](#interface-signals)
- [Operating Modes](#operating-modes)
- [Timing Specifications](#timing-specifications)
- [Protocol Integeration](#Protocol-Integeration)
- [Verification Plan](#verification-plan)
- [Design Verification Diagram](#design-verification-diagram)
- [SystemVerilog Assertions](#SystemVerilog-Assertions)
- [Register Abstraction Layer](#Register-Abstraction-Layer)
- [Additional Considerations](#additional-considerations)

## Introduction to APB

The Advanced Peripheral Bus (APB) is part of the Advanced Microcontroller Bus Architecture (AMBA) protocol family. It is designed for low-bandwidth control accesses, such as register interfaces on system peripherals. This makes APB an optimal choice for interfacing with peripherals that don't require high-performance data transfers.

### Key Benefits and Applications
- Low-power peripheral communication
- Simple interface design with minimal complexity
- Perfect for:
  - Register control interfaces
  - Low-speed peripherals
  - System configuration registers
  - Debug interfaces
  - Power management modules

## Specifications

### System Overview
- Clock Frequency: 10 MHz
- Reset: Active Low (PRESETn)
- Protocol: AMBA APB
- Data Width: 32-bit
- Address Width: 32-bit

### Design Implementation and verification
- APB Master implementation in `apb_master.v` https://edaplayground.com/x/kMSN
- APB Slave implementation in `apb_slave.v`   https://edaplayground.com/x/BQwq
- Top-level integration in `apb_top.v`        [to be completed]
### APB Master Specifications

The APB Master acts as a bridge between the system bus and APB peripherals, managing data transfers and protocol conversion. Key features include:

- Dual slave support with configurable address ranges
- Error detection and handling mechanisms
- Timeout counter for unresponsive slaves
- Configurable data and address widths
- Support for write strobe operations
- Protection signal handling

### APB Slave Specifications

The APB Slave implements a memory-mapped peripheral with the following features:

- Configurable memory depth (256 locations default)
- Byte-wise write enables
- Error detection for invalid accesses
- Address range checking
- Alignment verification

## Interface Signals

### Master Interface Signals

| Signal Name | Width | Direction | Description |
|------------|--------|-----------|-------------|
| PCLK | 1 | Input | System clock (10 MHz) |
| PRESETn | 1 | Input | Active low reset |
| PADDR | 32 | Output | Address bus |
| PWRITE | 1 | Output | Write/Read control |
| PSEL[1:0] | 2 | Output | Slave select signals |
| PENABLE | 1 | Output | Enable signal |
| PWDATA | 32 | Output | Write data bus |
| PRDATA | 32 | Input | Read data bus |
| PREADY | 1 | Input | Slave ready signal |
| PSLVERR | 1 | Input | Slave error response |
| PSTRB | 4 | Output | Write strobe signals |
| PPROT | 3 | Output | Protection type |

### Slave Interface Signals

| Signal Name | Width | Direction | Description |
|------------|--------|-----------|-------------|
| PCLK | 1 | Input | System clock (10 MHz) |
| PRESETn | 1 | Input | Active low reset |
| PSEL | 1 | Input | Slave select |
| PENABLE | 1 | Input | Enable signal |
| PADDR | 32 | Input | Address bus |
| PWRITE | 1 | Input | Write control |
| PWDATA | 32 | Input | Write data bus |
| PRDATA | 32 | Output | Read data bus |
| PREADY | 1 | Output | Ready signal |
| PSLVERR | 1 | Output | Error signal |
| PSTRB | 4 | Input | Write strobes |
| PPROT | 3 | Input | Protection type |

## Operating Modes

### Write Operation
1. **Setup Phase**
   - Assert PSEL
   - Set PWRITE high
   - Drive PADDR and PWDATA
   - PENABLE remains low

2. **Access Phase**
   - Assert PENABLE
   - Maintain PADDR, PWDATA, and PWRITE
   - Wait for PREADY assertion
   - Complete transfer on PREADY high

### Read Operation
1. **Setup Phase**
   - Assert PSEL
   - Set PWRITE low
   - Drive PADDR
   - PENABLE remains low

2. **Access Phase**
   - Assert PENABLE
   - Maintain PADDR and PWRITE
   - Sample PRDATA when PREADY is high
   - Complete transfer

## Timing Specifications

### APB Protocol Phases

1. **IDLE State**
   - Default state when no transfers required
   - PSEL and PENABLE deasserted

2. **Setup Phase (T1)**
   - One clock cycle duration
   - PSEL assertion
   - Address and control signals stable

3. **Access Phase (T2)**
   - PENABLE assertion
   - Data transfer occurs
   - Minimum one clock cycle duration
   - Extended by PREADY deassertion

## Protocol Integeration
[To be completed]

## Verification Plan
[Test cases    To be completed]
[Coverage Plan To be completed]

## Design Verification Diagram
[1-UVM DIAGRAM   To be completed]
[2-CLASS DIAGRAM To be completed]

## SystemVerilog Assertions
Master Assertions is done
[Slave , Top To be completed]

## RAL
[To be completed]

## Additional Considerations

### Error Handling
1. **Master Error Detection**
   - Address range violations
   - Timeout conditions
   - Slave errors (PSLVERR)
   - Write strobe errors

2. **Slave Error Detection**
   - Address alignment
   - Write strobe validation
   - Address range checking


### Debug Features
- Error status reporting
- Transfer monitoring
- State machine visibility

---
## APB Master-Slave Integration

### Multi-Slave Architecture
The APB master in this design supports integration with two slave peripherals, enabling efficient peripheral management and resource utilization.

### Address Mapping

Address mapping is crucial for proper system operation and provides several key benefits:

1. **Memory Organization**
   - Slave 1: 0x0000_0000 to 0x0000_FFFF (64KB)
   - Slave 2: 0x0001_0000 to 0x0001_FFFF (64KB)

2. **Key Benefits**
   - Prevents address conflicts
   - Enables modular design
   - Simplifies system debugging
   - Facilitates system expansion

3. **Implementation Details**
   ```verilog
   wire addr_in_slave1 = (current_addr >= ADDR_START_1) && (current_addr <= ADDR_END_1);
   wire addr_in_slave2 = (current_addr >= ADDR_START_2) && (current_addr <= ADDR_END_2);
   ```

### Error Scenarios and Handling

#### Master Error Scenarios

1. **Invalid Address Access**
   - Scenario: Address outside defined slave ranges
   - Detection: `addr_in_range = addr_in_slave1 || addr_in_slave2;`
   - Response: Sets error_status to INVALID_ADDR

2. **Timeout Error**
   - Scenario: Slave doesn't respond within 15 cycles
   - Detection: `timeout_counter == 4'hF`
   - Response: Aborts transaction, sets TIMEOUT_ERROR

3. **Write Strobe Error**
   - Scenario: All write strobes are zero during write
   - Detection: `strb_error = !READ_WRITE && (IN_STRB == 4'b0000);`
   - Response: Sets STRB_ERROR

4. **Slave Error Response**
   - Scenario: Slave asserts PSLVERR
   - Detection: `PSLVERR == 1'b1`
   - Response: Sets PSLV_ERROR

#### Slave Error Scenarios

1. **Address Alignment Error**
   ```verilog
   assign alignment_error = PSEL && ((PSTRB == 4'b1111 && local_addr[1:0] != 2'b00) ||
                                   (PSTRB == 4'b0011 && local_addr[0] != 1'b0));
   ```

2. **Out of Range Access**
   ```verilog
   assign addr_in_range = (PADDR >= SLAVE_START_ADDR) && (PADDR <= SLAVE_END_ADDR);
   ```

3. **Invalid Write Operation**
   ```verilog
   assign write_error = PSEL && PWRITE && (PSTRB == 4'b0000);
   ```

### Transfer Scenarios

#### Write Transfer
1. **Normal Write**
   ```
   IDLE → SETUP → ACCESS → IDLE
   - PSEL asserted in SETUP
   - PENABLE asserted in ACCESS
   - Write completes when PREADY is high
   ```

2. **Write with Wait States**
   ```
   IDLE → SETUP → ACCESS (PREADY low) → ACCESS (PREADY high) → IDLE
   - Slave extends transfer by keeping PREADY low
   - Master maintains signals until PREADY
   ```

#### Read Transfer
1. **Normal Read**
   ```
   IDLE → SETUP → ACCESS → IDLE
   - Address driven in SETUP
   - Data sampled in ACCESS when PREADY high
   ```

2. **Read with Error**
   ```
   IDLE → SETUP → ACCESS → ERROR → IDLE
   - PSLVERR detected
   - Transfer aborted
   - Error status updated
   ```

### System Integration Tips

1. **Clock Domain Considerations**
   - All slaves must operate in same clock domain
   - Synchronous reset distribution
   - Proper reset tree planning

2. **Address Decode Optimization**
   - Fast decode logic for better timing
   - Non-overlapping ranges
   - Default slave for undefined ranges

3. **Error Handling Strategy**
   - Centralized error logging
   - Error status reporting
   - Recovery mechanisms

4. **Performance Optimization**
   - Minimize wait states
   - Optimize address decoding
   - Efficient slave selection

End of Documentation
