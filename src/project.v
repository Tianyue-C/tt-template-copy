/*
 * Copyright (c) 2026 Tianyue
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module lif_unit #(
    parameter signed [7:0] THRESHOLD = 8'sd64
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [1:0]        shift_sel,   // 00: no leak, 01: >>>1, 10: >>>2, 11: >>>3
    input  wire signed [7:0] syn_current,
    output wire              spike_out,
    output reg  signed [7:0] mem
);

    reg  signed [7:0] mem_leak;
    wire signed [7:0] mem_next;

    always @(*) begin
        case (shift_sel)
            2'b00: mem_leak = mem;
            2'b01: mem_leak = mem >>> 1;
            2'b10: mem_leak = mem >>> 2;
            2'b11: mem_leak = mem >>> 3;
            default: mem_leak = mem >>> 1;
        endcase
    end

    assign mem_next  = mem_leak + syn_current;
    assign spike_out = (mem_next >= THRESHOLD) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem <= 8'sd0;
        end else if (spike_out) begin
            mem <= 8'sd0;
        end else begin
            mem <= mem_next;
        end
    end

endmodule

module tt_um_tianyue_snn_array (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // ui_in[3:0]: 4 spike inputs
    // ui_in[5:4]: leak decay shift_sel (00: none, 01: >>>1, 10: >>>2, 11: >>>3)
    // ui_in[7:6]: mode
    //   00: 4 independent LIF integrators (w = 32)
    //   01: 4 pairwise Spiking AND gates (0&1, 1&2, 2&3, 0&3; w = 32)
    //   10: Excitatory/Inhibitory mix (+64 on self, -32 on neighbor)
    //   11: 4-stage spiking cascade chain (in[0] -> N0 -> N1 -> N2 -> N3; w = 64)
    wire [3:0] spike_in  = ui_in[3:0];
    wire [1:0] shift_sel = ui_in[5:4];
    wire [1:0] mode      = ui_in[7:6];

    reg  signed [7:0] syn0, syn1, syn2, syn3;
    wire [3:0]        spikes;
    wire signed [7:0] mem0, mem1, mem2, mem3;

    always @(*) begin
        case (mode)
            2'b00: begin
                syn0 = spike_in[0] ? 8'sd32 : 8'sd0;
                syn1 = spike_in[1] ? 8'sd32 : 8'sd0;
                syn2 = spike_in[2] ? 8'sd32 : 8'sd0;
                syn3 = spike_in[3] ? 8'sd32 : 8'sd0;
            end
            2'b01: begin
                syn0 = (spike_in[0] ? 8'sd32 : 8'sd0) + (spike_in[1] ? 8'sd32 : 8'sd0);
                syn1 = (spike_in[1] ? 8'sd32 : 8'sd0) + (spike_in[2] ? 8'sd32 : 8'sd0);
                syn2 = (spike_in[2] ? 8'sd32 : 8'sd0) + (spike_in[3] ? 8'sd32 : 8'sd0);
                syn3 = (spike_in[0] ? 8'sd32 : 8'sd0) + (spike_in[3] ? 8'sd32 : 8'sd0);
            end
            2'b10: begin
                syn0 = (spike_in[0] ? 8'sd64 : 8'sd0) - (spike_in[1] ? 8'sd32 : 8'sd0);
                syn1 = (spike_in[1] ? 8'sd64 : 8'sd0) - (spike_in[2] ? 8'sd32 : 8'sd0);
                syn2 = (spike_in[2] ? 8'sd64 : 8'sd0) - (spike_in[3] ? 8'sd32 : 8'sd0);
                syn3 = (spike_in[3] ? 8'sd64 : 8'sd0) - (spike_in[0] ? 8'sd32 : 8'sd0);
            end
            2'b11: begin
                syn0 = spike_in[0] ? 8'sd64 : 8'sd0;
                syn1 = spikes[0]   ? 8'sd64 : 8'sd0;
                syn2 = spikes[1]   ? 8'sd64 : 8'sd0;
                syn3 = spikes[2]   ? 8'sd64 : 8'sd0;
            end
            default: begin
                syn0 = 8'sd0;
                syn1 = 8'sd0;
                syn2 = 8'sd0;
                syn3 = 8'sd0;
            end
        endcase
    end

    lif_unit u_lif0 (.clk(clk), .rst_n(rst_n), .shift_sel(shift_sel), .syn_current(syn0), .spike_out(spikes[0]), .mem(mem0));
    lif_unit u_lif1 (.clk(clk), .rst_n(rst_n), .shift_sel(shift_sel), .syn_current(syn1), .spike_out(spikes[1]), .mem(mem1));
    lif_unit u_lif2 (.clk(clk), .rst_n(rst_n), .shift_sel(shift_sel), .syn_current(syn2), .spike_out(spikes[2]), .mem(mem2));
    lif_unit u_lif3 (.clk(clk), .rst_n(rst_n), .shift_sel(shift_sel), .syn_current(syn3), .spike_out(spikes[3]), .mem(mem3));

    // uo_out[3:0]: live spikes from all 4 LIF neurons
    // uo_out[7:4]: positive membrane activity flags (mem > 0)
    assign uo_out  = {(mem3 > 8'sd0), (mem2 > 8'sd0), (mem1 > 8'sd0), (mem0 > 8'sd0), spikes};
    // uio_out[7:0]: live 8-bit signed membrane potential of Neuron 0
    assign uio_out = mem0;
    assign uio_oe  = 8'hFF;

    wire _unused = &{ena, uio_in, 1'b0};

endmodule
