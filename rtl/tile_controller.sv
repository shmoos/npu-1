`timescale 1ns/1ps

module tile_controller
  import npu_pkg::*;
#(parameter int unsigned WATCHDOG_CYCLES = 50000)
(
  input  logic        clk,
  input  logic        rst_n,

  // Host Control & Configuration Inputs
  input  logic        start_cmd,
  input  logic        soft_reset_cmd,
  input  logic [15:0] cfg_k,
  input  logic [2:0]  cfg_m_valid,
  input  logic [2:0]  cfg_n_valid,
  input  logic [1:0]  cfg_mode,
  input  logic [31:0] cfg_command_seq,
  input  logic [31:0] cfg_requant_mult,
  input  logic [5:0]  cfg_requant_shift,
  input  int32_t      cfg_bias [4],

  // Sticky Status Outputs & Latched Registers
  output logic        status_busy,
  output logic        status_done,
  output logic        status_error,
  input  logic        status_done_w1c,
  input  logic        status_error_w1c,
  output logic [31:0] error_code_out,
  output logic [31:0] completed_seq_out,
  output logic [63:0] cycle_count_out,

  // Control Signals to Operand Buffers
  output logic        buf_compute_re,
  output logic [9:0]  buf_k_addr,

  // Control Signals to Skew Feeder & Array
  output logic        array_clear,
  output logic        array_step,
  output logic        a_valid_feeder [4],
  output logic        b_valid_feeder [4],

  // Control Signals to Post-Processor & Result Buffer
  output logic        post_valid_in,
  output int32_t      post_acc_in,
  output int32_t      post_bias_in,
  output npu_mode_e   post_mode_in,
  output logic [31:0] post_mult_in,
  output logic [5:0]  post_shift_in,

  output logic        result_store_en,
  output logic [1:0]  result_store_row,
  output logic [1:0]  result_store_col,

  // Array Accumulators Input
  input  int32_t      array_acc_in [4][4],

  // Post-Processor Output Handshake
  input  logic        post_valid_out
);

  typedef enum logic [3:0] {
    ST_IDLE        = 4'd0,
    ST_CHECK       = 4'd1,
    ST_CLEAR       = 4'd2,
    ST_PREFETCH    = 4'd3,
    ST_RUN         = 4'd4,
    ST_DRAIN       = 4'd5,
    ST_POSTPROCESS = 4'd6,
    ST_DONE        = 4'd7,
    ST_ERROR       = 4'd8
  } state_e;

  state_e state;

  // Latched Configuration Registers
  logic [15:0] k_latched;
  logic [2:0]  m_latched;
  logic [2:0]  n_latched;
  npu_mode_e   mode_latched;
  logic [31:0] seq_latched;
  logic [31:0] mult_latched;
  logic [5:0]  shift_latched;
  int32_t      bias_latched [4];

  // Internal Step Counters
  logic [15:0] k_counter;
  logic [3:0]  drain_counter;
  logic [4:0]  post_counter;  // 0..16 inputs fed
  logic [4:0]  store_counter; // 0..16 outputs stored

  // 64-bit Cycle Counter & Watchdog
  logic [63:0] active_cycles;
  logic [15:0] watchdog_timer;
  localparam logic [15:0] WATCHDOG_LIMIT = 16'(WATCHDOG_CYCLES);

  // synthesis translate_off
  initial assert (WATCHDOG_CYCLES > 0 && WATCHDOG_CYCLES <= 65535)
    else $fatal(1, "WATCHDOG_CYCLES must fit the 16-bit nonzero timer");
  // synthesis translate_on

  // Status and Error Registers
  logic        sticky_done;
  logic        sticky_error;
  logic [31:0] latched_error_code;
  logic [31:0] latched_completed_seq;

  assign status_busy  = (state != ST_IDLE);
  assign status_done  = sticky_done;
  assign status_error = sticky_error;
  assign error_code_out    = latched_error_code;
  assign completed_seq_out = latched_completed_seq;

  // Direct alignment for result buffer storage
  assign result_store_en  = post_valid_out;
  assign result_store_row = store_counter[3:2];
  assign result_store_col = store_counter[1:0];

  // FSM and Execution
  always_ff @(posedge clk) begin
    if (!rst_n || soft_reset_cmd) begin
      state                 <= ST_IDLE;
      k_counter             <= 16'd0;
      drain_counter         <= 4'd0;
      post_counter          <= 5'd0;
      store_counter         <= 5'd0;
      active_cycles         <= 64'd0;
      cycle_count_out       <= 64'd0;
      watchdog_timer        <= 16'd0;
      sticky_done           <= 1'b0;
      sticky_error          <= 1'b0;
      latched_error_code    <= ERR_NONE;
      latched_completed_seq <= 32'd0;

      array_clear     <= 1'b0;
      array_step      <= 1'b1;
      buf_compute_re  <= 1'b0;
      buf_k_addr      <= 10'd0;
      post_valid_in   <= 1'b0;
      for (int i = 0; i < 4; i++) a_valid_feeder[i] <= 1'b0;
      for (int j = 0; j < 4; j++) b_valid_feeder[j] <= 1'b0;
    end else begin
      // W1C Handling
      if (status_done_w1c)  sticky_done  <= 1'b0;
      if (status_error_w1c) sticky_error <= 1'b0;

      // Watchdog and Cycle Counter during active computation
      if (state != ST_IDLE) begin
        active_cycles  <= active_cycles + 64'd1;
        watchdog_timer <= watchdog_timer + 16'd1;

      end

      case (state)
        ST_IDLE: begin
          watchdog_timer  <= 16'd0;
          array_clear     <= 1'b0;
          array_step      <= 1'b1;
          buf_compute_re  <= 1'b0;
          post_valid_in   <= 1'b0;
          for (int i = 0; i < 4; i++) a_valid_feeder[i] <= 1'b0;
          for (int j = 0; j < 4; j++) b_valid_feeder[j] <= 1'b0;

          if (start_cmd) begin
            active_cycles <= 64'd0;
            sticky_done   <= 1'b0; // Clear stale done

            // Latch configuration
            k_latched     <= cfg_k;
            m_latched     <= cfg_m_valid;
            n_latched     <= cfg_n_valid;
            mode_latched  <= npu_mode_e'(cfg_mode);
            seq_latched   <= cfg_command_seq;
            mult_latched  <= cfg_requant_mult;
            shift_latched <= cfg_requant_shift;
            for (int b = 0; b < 4; b++) bias_latched[b] <= cfg_bias[b];

            state <= ST_CHECK;
          end
        end

        ST_CHECK: begin
          // Validate configuration parameters
          if (k_latched < 16'd1 || k_latched > 16'd1024) begin
            latched_error_code <= ERR_INVALID_K;
            sticky_error       <= 1'b1;
            state              <= ST_ERROR;
          end else if (m_latched < 3'd1 || m_latched > 3'd4) begin
            latched_error_code <= ERR_INVALID_M;
            sticky_error       <= 1'b1;
            state              <= ST_ERROR;
          end else if (n_latched < 3'd1 || n_latched > 3'd4) begin
            latched_error_code <= ERR_INVALID_N;
            sticky_error       <= 1'b1;
            state              <= ST_ERROR;
          end else if (mode_latched > MODE_REQUANT_INT8) begin
            latched_error_code <= ERR_INVALID_MODE;
            sticky_error       <= 1'b1;
            state              <= ST_ERROR;
          end else if (mode_latched == MODE_REQUANT_INT8 && (mult_latched == 32'd0 || mult_latched[31] || shift_latched > 6'd62)) begin
            latched_error_code <= ERR_INVALID_REQUANT;
            sticky_error       <= 1'b1;
            state              <= ST_ERROR;
          end else begin
            // Configuration valid -> Proceed to clear array
            array_clear <= 1'b1;
            state       <= ST_CLEAR;
          end
        end

        ST_CLEAR: begin
          array_clear <= 1'b0;
          // Trigger prefetch of k = 0
          buf_compute_re <= 1'b1;
          buf_k_addr     <= 10'd0;
          k_counter      <= 16'd0;
          state          <= ST_PREFETCH;
        end

        ST_PREFETCH: begin
          // RAM synchronous read completes this cycle
          // Prepare to drive first operands into skew feeder
          buf_compute_re <= 1'b1;
          buf_k_addr     <= 10'd1;
          k_counter      <= 16'd0;

          // Assert valid for active rows & columns
          for (int i = 0; i < 4; i++) a_valid_feeder[i] <= (i < m_latched);
          for (int j = 0; j < 4; j++) b_valid_feeder[j] <= (j < n_latched);

          state <= ST_RUN;
        end

        ST_RUN: begin
          // Stream operands for K cycles
          if (k_counter + 16'd1 < k_latched) begin
            k_counter      <= k_counter + 16'd1;
            buf_compute_re <= 1'b1;
            buf_k_addr     <= k_counter[9:0] + 10'd2;
            for (int i = 0; i < 4; i++) a_valid_feeder[i] <= (i < m_latched);
            for (int j = 0; j < 4; j++) b_valid_feeder[j] <= (j < n_latched);
          end else begin
            // Reached K -> Transition to DRAIN
            buf_compute_re <= 1'b0;
            drain_counter  <= 4'd0;
            for (int i = 0; i < 4; i++) a_valid_feeder[i] <= 1'b0;
            for (int j = 0; j < 4; j++) b_valid_feeder[j] <= 1'b0;
            state          <= ST_DRAIN;
          end
        end

        ST_DRAIN: begin
          // 6 cycles to flush skew pipelines and 4x4 array
          if (drain_counter < 4'd6) begin
            drain_counter <= drain_counter + 4'd1;
          end else begin
            // Computation finished! Initialize sequential post-processor
            post_counter  <= 5'd0;
            store_counter <= 5'd0;
            state         <= ST_POSTPROCESS;
          end
        end

        ST_POSTPROCESS: begin
          // Feed elements 0..15 into post-processor
          if (post_counter < 5'd16) begin
            logic [1:0] r, c;
            r = post_counter[3:2];
            c = post_counter[1:0];

            post_valid_in <= 1'b1;
            post_acc_in   <= array_acc_in[r][c];
            post_bias_in  <= bias_latched[c];
            post_mode_in  <= mode_latched;
            post_mult_in  <= mult_latched;
            post_shift_in <= shift_latched;

            post_counter  <= post_counter + 5'd1;
          end else begin
            post_valid_in <= 1'b0;
          end

          // Advance store counter as post-processor outputs arrive
          if (post_valid_out) begin
            store_counter <= store_counter + 5'd1;
            if (store_counter == 5'd15) begin
              state <= ST_DONE;
            end
          end
        end

        ST_DONE: begin
          sticky_done           <= 1'b1;
          latched_completed_seq <= seq_latched;
          cycle_count_out       <= active_cycles;
          state                 <= ST_IDLE;
        end

        ST_ERROR: begin
          sticky_error    <= 1'b1;
          cycle_count_out <= active_cycles;
          state           <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
      // Timeout overrides active work, but terminal states must retire to IDLE.
      // Re-entering ST_ERROR here would retain BUSY until the timer wrapped.
      if (state != ST_IDLE && state != ST_ERROR && state != ST_DONE &&
          watchdog_timer >= WATCHDOG_LIMIT) begin
        state <= ST_ERROR;
        latched_error_code <= ERR_WATCHDOG_TIMEOUT;
        sticky_error <= 1'b1;
        post_valid_in <= 1'b0;
        buf_compute_re <= 1'b0;
        array_clear <= 1'b1;
        for (int i=0;i<4;i++) begin a_valid_feeder[i]<=0; b_valid_feeder[i]<=0; end
      end
    end
  end

endmodule
