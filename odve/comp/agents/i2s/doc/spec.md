# I2S (Inter-IC Sound) - protocol summary for verification

What the `odve_i2s` agent, its DUT and its checks are built on. Section and
table numbers below are the ones of the documents as read; nothing else is
cited.

## 1. References

| # | Title | Version / date | Where | Access | Used for |
|---|---|---|---|---|---|
| [UM11732] | NXP UM11732 *I2S bus specification* | Rev. 3.0, 17 February 2022 (reconstruction of the Philips Semiconductors *I2S bus specification*, February 1986, revised 5 June 1996; "master/slave" renamed "controller/target") | https://www.nxp.com/docs/en/user-manual/UM11732.pdf | public | the I2S format, roles, timing (sections 2, 3, 3.1, 3.2, 4, Tables 1-3, Figures 1-3) |
| [PHILIPS] | Philips Semiconductors *I2S bus specification* | Feb. 1986, rev. June 5, 1996 | e.g. https://www.fdi.ucm.es/profesor/mendias/PSyD/docs/I2SBUS.pdf | public | not read separately: UM11732 rev. 3.0 states it is this document reconstructed |
| [MCHP] | Microchip PIC32CK1025/2051 data sheet DS60001795H, chapter 51 *Inter-IC Sound Controller (I2S)*, section 51.5.12.5 *Audio Protocol Modes* | DS60001795H | https://onlinedocs.microchip.com/oxy/GUID-23E87D1E-D394-4999-8B0C-DC4246E39160-en-US-8/GUID-08E33634-5D25-43CD-BDE4-6AAB5582624C.html | public | left-justified, right-justified and PCM/DSP (TDM) variants, which are not part of UM11732 |
| [TI] | TI PCM1840 data sheet, SBAS989, section 7.3.2 *Audio Serial Interfaces* (7.3.2.1 TDM, 7.3.2.2 I2S, 7.3.2.3 LJ) | April 2019 | https://www.ti.com/document-viewer/lit/html/SBAS989/audio-serial-interfaces-t5097758-14 | public | only that TDM/I2S/LJ coexist as selectable formats and that the device is clock master or slave by pin; the section bodies were not available in the copy read |

The I2S format itself is defined only by [UM11732]. Left-justified,
right-justified and TDM/DSP are de-facto industry variants with no single
standard; the agent follows [MCHP] for them and states every choice made
where vendors differ (section 3.3).

## 2. Signals and electrical model

| Signal | Driven by | Meaning |
|---|---|---|
| SCK | clock controller | continuous serial (bit) clock [UM11732 3] |
| WS  | clock controller | word select: channel of the word being sent (I2S/LJ/RJ), or frame sync (TDM) [UM11732 3.2] |
| SD  | transmitter      | serial data, two's complement, MSB first [UM11732 3.1] |
| MCLK| system (optional) | master/system clock, often 256 fs; not part of [UM11732] |

- All lines are **push-pull** with a single driver each. "The device
  generating SCK and WS is the controller" [UM11732 3]; the controller may be
  the transmitter, the receiver or a separate system controller
  [UM11732 2, Figure 1]. Direction (transmitter/receiver) and clock role
  (controller/target) are therefore independent.
- Electrical levels (VL < 0.4 V, VH > 2.4 V output; VIL 0.8 V, VIH 2.0 V
  input, [UM11732 5]) are not modelled: the TB is logic-level.
- In the TB, each possible driver has its own value + output enable
  (`a_*` agent, `d_*` DUT) and the interface muxes them; two enables on one
  line at once is reported as contention by the monitor.

## 3. Frame formats

Notation: one character = one SCK period. Position `p` counts the SCK
periods of a frame from the frame start (`p = 0`, the period in which WS
takes the level of the first slot); `s` = slot length (16 or 32 SCK
periods), `w` = word length (16, 24, 32; `w <= s`), `N` = slots x `s` =
frame length.

### 3.1 Edges

"Serial data must be latched into the receiver on the leading edge of the
serial clock" [UM11732 3.1]; data may be launched on either edge, with
restrictions for the leading edge. The agent and the DUT launch SD and WS
on the **falling** edge and sample on the **rising** edge, as the task
brief and common practice require; the target latches WS on the leading
edge [UM11732 3.2].

```
SCK  ‾‾\__/‾‾\__/‾‾\__/‾‾\__/
SD   ==X=====X=====X=====X===      change after the falling edge (tdtr)
          ^     ^     ^            sampled on the rising edge (tsr before, thr after)
```

### 3.2 I2S (Philips) [UM11732 3.1, 3.2, Figure 1]

- WS = 0: channel 1 (left); WS = 1: channel 2 (right).
- "The WS line changes one clock period before the MSB is transmitted";
  "the transmitter always sends the MSB of the next word one clock period
  after the WS changes". The MSB position is fixed, the LSB position depends
  on the word length; bits after the LSB are 0 ("least significant data
  bits are set to '0'"); a receiver ignores bits beyond its word length and
  zero-fills missing ones.
- The LSB of the right word falls into `p = 0` of the next frame (when
  `w = s`).

```
          p: N-1 | 0   1   2  ...  w   w+1 ... s-1 | s  s+1 ... | N-1 | 0 (next)
SCK        _/‾\_/‾\_/‾\_/‾\_ ... _/‾\_/‾\_ ... _/‾\_/‾\_/‾\_ ... _/‾\_/‾\_
WS         ‾‾‾‾‾\______________ left ___________/‾‾‾‾‾ right ‾‾‾‾‾‾‾\_____
SD          R.LSB| x  L.MSB ...  L.LSB  0  ...  0 | x  R.MSB ...       |R.LSB(w=s)
                   (x = previous word's last bit / 0)
```

### 3.3 Left-justified, right-justified [MCHP 51.5.12.5]

- **LJ**: WS = 1 left, WS = 0 right (the opposite of I2S); the MSB is in
  the same SCK period as the WS change (`p = 0` for left, `p = s` for right).
- **RJ**: same WS polarity as LJ; the word ends with its slot: the LSB is in
  the last SCK period before the WS change, MSB at `p = s - w` (left) and
  `2s - w` (right); the bits before the MSB are 0 when transmitting.

```
LJ  WS ___/‾‾‾‾‾‾‾‾‾ left ‾‾‾‾‾‾‾‾\_______ right ______/‾‾‾
    SD    |MSB ... LSB 0 ... 0   |MSB ... LSB 0 ... 0  |MSB
RJ  WS ___/‾‾‾‾‾‾‾‾‾ left ‾‾‾‾‾‾‾‾\_______ right ______/‾‾‾
    SD    |0 ... 0 MSB ... LSB   |0 ... 0 MSB ... LSB  |0
```

Where vendors differ, the choices made: LJ/RJ "left" = WS high (as
[MCHP]); RJ padding = zeros, not sign extension (as [MCHP] for
transmission).

### 3.4 TDM / DSP [MCHP 51.5.12.5]

- A frame sync on WS marks the frame; slots follow back to back (slot `k`
  at `p = 1 + k*s`), word left-aligned in its slot.
- Choices made among the variants [MCHP] lists: frame sync **one SCK
  period wide, high**, at `p = 0`; MSB of slot 0 **one SCK period after**
  the frame sync rises (DSP "mode A", like I2S); 2, 4 or 8 slots.

```
WS  ___/‾\________________________________________________/‾\____
SD     | x |slot0 MSB..LSB 0..|slot1 ...|  ...  |slot n-1   |   |slot0
     p: 0   1                  s+1                            0
```

### 3.5 Mono

Not defined by [UM11732]. Here: a mono stream sends the same sample in both
channels of a stereo frame (the monitor checks left == right).

## 4. Roles and frame synchronisation

- Controller: generates SCK (fixed mark/space ratio, [UM11732 Table 3
  note 2]) and WS. Target: takes SCK and WS as inputs and "derives
  synchronous timing of the serial data" from the WS change one clock before
  the MSB [UM11732 3.2].
- A target (and the monitor) recognises a frame start as the WS transition
  into the first slot's level (I2S: 1 -> 0, LJ/RJ: 0 -> 1, TDM: 0 -> 1 of
  the pulse) between two rising edges. For LJ/RJ the first data bit shares
  its SCK period with that WS change, so a target transmitter needs the
  previous frame to know where the next one starts: it sends idle frames
  until it has seen one frame start and then relies on the constant frame
  length.

## 5. Timing parameters [UM11732 4, Figures 2-3, Table 3]

All relative to the clock period T (the spec specifies them so):

| Parameter | Requirement | Modelled / checked |
|---|---|---|
| SCK HIGH tHC, LOW tLC | >= 0.35 T (controller generates a fixed ratio) | controllers generate 50 %; monitor checks >= 0.35 T every period (`I2S_TIMING`) |
| receiver set-up tsr (SD, WS) | >= 0.2 T before the rising edge | monitor checks (`I2S_TIMING`), negative test `i2s_timing_err` |
| receiver hold thr | >= 0 | changes coincident with the rising edge are ignored by the set-up check; not checked otherwise |
| transmitter delay tdtr | <= 0.8 T after the rising edge | not checked separately (implied by tsr for a 50 % clock) |
| transmitter hold thtr | >= 0 | not checked |
| clock rise time tRC | <= 0.15 Ttr (target mode) | not modelled (zero-time edges) |

TB scaling: SCK T = 160 ns by default (`sck_half_ns = 80`; [UM11732 Table 1]
uses 400 ns at 2.5 MHz), the DUT runs on a 10 ns system clock and
oversamples SCK as a target.

## 6. Error conditions

The I2S bus has no acknowledge, parity or error signalling. What a monitor
can detect, and the agent does:

| Condition | Detected as |
|---|---|
| WS at a level the frame position does not allow (glitch, early/late edge) | `I2S_WS` |
| frame start after the wrong number of SCK periods / no frame start after N periods (constant frame length) | `I2S_FRAME` |
| SD/WS unknown at a rising edge | `I2S_X` |
| 1 outside the word bits of a slot | `I2S_PAD` |
| mono frame with left != right | `I2S_MONO` |
| SCK duty < 0.35 T, set-up < 0.2 T | `I2S_TIMING` |
| two drivers enabled on a line | `I2S_CONTENTION` |

After `I2S_WS`/`I2S_FRAME` the monitor drops the frame in progress and
resynchronises on the next frame start (the DUT's receiver does the same).

## 7. Modelled / not modelled

Modelled:
- I2S, LJ, RJ, TDM (2/4/8 slots) formats; word length 16/24/32 in 16/32-SCK slots.
- Transmitter and receiver, each as clock controller or target, in any combination.
- Frame reconstruction, WS/frame-length checks, SCK duty and SD/WS set-up checks, contention.
- Mono (duplicated sample), idle (all-zero) frames, back-to-back frames.
- Controller error injection: WS glitch, frame one SCK short.

Not modelled:
- Different word lengths at transmitter and receiver (truncation /
  zero fill, [UM11732 3.1]): agent, monitor and DUT always share one word
  length.
- Data launched on the rising edge [UM11732 3.1 allows it with
  restrictions]; WS/SD inverted polarities; LJ/RJ with WS low = left; TDM
  with a word-wide frame sync or zero-delay ("mode B") sync.
- MCLK beyond a free-running signal; sample-rate / MCLK ratios.
- Electrical levels, rise times (tRC), transmitter delay/hold (tdtr, thtr),
  receiver hold (thr).
- Sign-extended padding in RJ.
