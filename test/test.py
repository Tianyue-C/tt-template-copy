# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


async def reset_dut(dut):
    dut.ui_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start 4-Neuron 0-DSP LIF Array test")

    # 25 MHz clock (40 ns)
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.uio_in.value = 0
    await reset_dut(dut)

    assert int(dut.uio_oe.value) == 0xFF

    # Mode 00: Independent integrators, no leak (shift_sel=00), w=32 -> fires on 2nd cycle
    dut.ui_in.value = 0b00_00_1010  # mode=00, shift=00, in=1010 (N1 and N3)
    await RisingEdge(dut.clk)
    assert (int(dut.uo_out.value) & 0xF) == 0b0000
    await RisingEdge(dut.clk)
    assert (int(dut.uo_out.value) & 0xF) == 0b1010

    # Mode 01: Pairwise Spiking AND, shift_sel=01 (Beta=0.5)
    await reset_dut(dut)
    dut.ui_in.value = 0b01_01_0011  # mode=01, shift=01, in[1:0]=11 -> N0 fires
    await RisingEdge(dut.clk)
    assert (int(dut.uo_out.value) & 0xF) == 0b0001

    # Mode 10: Excitatory/Inhibitory mix (+64 self, -32 neighbor)
    await reset_dut(dut)
    dut.ui_in.value = 0b10_01_0011  # in0=1, in1=1 -> N0 gets +64-32=32 (no fire), N1 gets +64 (fires)
    await RisingEdge(dut.clk)
    assert (int(dut.uo_out.value) & 0xF) == 0b0010

    # Mode 11: 4-stage cascade (in0 -> N0 -> N1 -> N2 -> N3)
    await reset_dut(dut)
    dut.ui_in.value = 0b11_01_0001  # mode=11, shift=01, in0=1 -> all 4 fire combinationally along chain
    await RisingEdge(dut.clk)
    assert (int(dut.uo_out.value) & 0xF) == 0b1111
