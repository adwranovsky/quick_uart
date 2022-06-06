# `quick_uart`
Quickly add UART TX and RX interfaces to an FPGA progject.

## Description

## `quick_uart_tx` module

### Parameters
#### `CLK_FREQ_HZ`
The input clock frequency. The UART baud rate. Ignored if DIV is manually set.
#### `BAUD`
The UART baud rate. Ignored if DIV is manually set.
#### `DIV`
The number of system clock cycles per bit. By default it is calculated from `CLK_FREQ_HZ` and `BAUD`, but can optionally
be manually set.
#### `IDLE_VALUE`
The value that `tx_o` should idle at when not transmitting.
#### `DATA_BITS`
The number of data bits per transfer
#### `STOP_BITS`
The number of stop bits at the end of the transfer. Each stop bit takes a value of `IDLE_VALUE`.
#### `START_BITS`
The number of start bits at the beginning of a transfer. Each start bit takes a value of `~IDLE_VALUE`.

### Ports
#### `clk_i`
The system clock.
#### `rst_i`
An active high reset synchronous with `clk_i`.
#### `busy_o`
Indicates when the device is busy transmitting, though when low it doesn't necessarily indicate that the device is ready
to receive more data. Hook up to an LED for a visual indicator of when the device is transmitting.
#### `ready_o`
Indicates that the module is ready to accept new data for transmission. The UART begins transmitting only when both
`valid_i` and `ready_o` are high on the same clock cycle.
#### `valid_i`
Indicates that `data_i` is valid. The UART begins transmitting only when both `valid_i` and `ready_o` are high on the
same clock cycle.
#### `data_i`
The data to write out serially on `tx_o`. The least significant bit is sent first.
#### `tx_o`
The UART serial output.

## `quick_uart_rx` module
### Parameters
#### `CLK_FREQ_HZ`
The input clock frequency. The UART baud rate. Ignored if DIV is manually set.
#### `BAUD`
The UART baud rate. Ignored if DIV is manually set.
#### `DIV`
The number of system clock cycles per bit. By default it is calculated from `CLK_FREQ_HZ` and `BAUD`, but can optionally
be manually set.
#### `IDLE_VALUE`
The value that `tx_o` should idle at when not transmitting.
#### `DATA_BITS`
The number of data bits per transfer
#### `STOP_BITS`
The number of stop bits at the end of the transfer. Each stop bit takes a value of `IDLE_VALUE`.
#### `START_BITS`
The number of start bits at the beginning of a transfer. Each start bit takes a value of `~IDLE_VALUE`.

### Ports
#### `clk_i`
The system clock.
#### `rst_i`
An active high reset synchronous with `clk_i`.
#### `busy_o`
Indicates when the device is busy receiving, though `data_o` may be valid despite `busy_o` being high. Hook up to an LED
for a visual indicator of when the device is receiving.
#### `ready_i`
Raise high when the data sink is ready to accept more data. The module's internal buffer is only flushed when `ready_i`
and `valid_o` are high on the same clock cycle.
#### `valid_o`
Indicates that the UART has completed receiving a whole word and that `data_o` and `data_dropped_o` are valid. The
module's internal buffer is only flushed when `ready_i` and `valid_o` are high on the same clock cycle.
#### `data_o`
The data most recently received serially on `rx_i`. Valid when `valid_o` is high. The least significant bit is the first
received on `rx_i`.
#### `data_dropped_o`
Indicates that the UART has finished receiving at least two bytes since the last `ready_i`/`valid_o` handshake, and
therefore had to drop a byte. Only valid when `valid_o` is high, and gets cleared on a `ready_i`/`valid_o` handshake.
#### `rx_i`
The UART serial input. There is no CDC synchronizer on this input, so make sure to add one external to this module.

## Testing
Testing is admittedly bare bones and uses a testbench generated from a SystemVerilog cover statement.

## Dependencies
`quick_spi` depends on a few cores from my cores library, which you can find here:
[CoreOrchard](https://github.com/adwranovsky/CoreOrchard)

## License
Copyright 2022 Alex Wranovsky.

This work is licensed under the CERN-OHL-W v2, a weakly reciprocal license for hardware. You may find the full
license text here if you have not received it with this source code distribution:

https://ohwr.org/cern_ohl_w_v2.txt
