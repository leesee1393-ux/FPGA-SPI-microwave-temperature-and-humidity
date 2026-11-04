# SPI Slave integration

Mode 0, MSB first: hold CS low for 16 SCK cycles. Send address in
cycles 1–8 and dummy 0x00 in cycles 9–16; sample response on rising
edges 9–16. MISO bit 7 is prepared after falling edge 8.

| Address | Response |
|---|---|
| 0x00 | Temperature integer byte (25.30 -> 25) |
| 0x01 | Humidity integer byte |
| 0x02 | Distance cm bits 7:0 |
| 0x03 | Distance cm bits 15:8 |
| 0xF0 | Self-test 0xA5 |
| 0xF1 | Self-test 0x5A |
| Other | 0x00 |

Latest values are updated only on the respective sensor valid pulses.
Before the first valid measurement they are zero. All sensor values are
snapshotted at selection, so each response is stable during transmission.
Separate distance-byte transactions can span an update: read MSB/LSB/MSB
and retry if the two MSBs differ. No freshness/status/ACK is defined by
the supplied diagrams. Sensor measurement continues independently.

100 MHz system clock: use SCK at most 1 MHz (high/low at least 500 ns),
CS setup, hold and high time at least 100 ns. This implementation uses
two-stage input synchronizers and system-clock edge detection, not SCK
as a fabric clock. CS high immediately releases MISO. Extra clocks after
16 are ignored. CS high aborts any partial transaction.

Self-test does not depend on sensor valid signals. For the master-board
check, transmit `[F0 00]` and expect `A5` during the second byte, then
transmit `[F1 00]` and expect `5A`. The first MISO byte is ignored; this
is an address/response protocol, not MOSI loopback.

Slave LEDs:

| LED | Meaning |
|---|---|
| 7:0 | Last received address byte |
| 8 | Toggles after each complete address byte (Write received) |
| 9 | Toggles after each complete response byte (Read sent) |
| 10 | Last address was valid |
| 11 | Invalid address or aborted frame |
| 12 | Last valid address was F0/F1 self-test |
| 14:13 | Off |
| 15 | On while CS is low (START through STOP) |

Slave wiring (new JC assignment, match the master's signal names):

| Signal | Slave Pmod | FPGA pin |
|---|---|---|
| SCK | JC1 | K17 |
| CS_n | JC2 | M18 |
| MOSI | JC3 | N17 |
| MISO | JC4 | P18 |

Connect common GND and use 3.3 V logic. Existing JA sensors and JB UART
assignments are unchanged. Rebuild the project before programming; older
top_checked.bit files do not contain this SPI implementation.
