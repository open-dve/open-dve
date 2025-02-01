`include "Verification_component.sv"
module apb4_master_tb();
  // Parameters
  parameter DATA_WIDTH    = 32;
  parameter ADDRESS_WIDTH = 32;
  parameter STRB_WIDTH    = DATA_WIDTH/8;
  parameter CLK_PERIOD    = 10;

  // Signals declaration
  reg                         PCLK;
  reg                         PRESETn;
  reg  [ADDRESS_WIDTH-1:0]    apb_write_paddr;
  reg  [ADDRESS_WIDTH-1:0]    apb_read_paddr;
  reg  [DATA_WIDTH-1:0]       apb_write_data;
  reg                         READ_WRITE;
  reg                         transfer;
  reg  [STRB_WIDTH-1:0]       IN_STRB;
  reg  [DATA_WIDTH-1:0]       PRDATA;
  reg                         PREADY;
  reg                         PSLVERR;

  // Outputs
  wire [DATA_WIDTH-1:0]       apb_read_data_out;
  wire                        transfer_error;
  wire [3:0]                  error_status;
  wire                        PSEL1;
  wire                        PSEL2;
  wire                        PENABLE;
  wire [ADDRESS_WIDTH-1:0]    PADDR;
  wire                        PWRITE;
  wire [DATA_WIDTH-1:0]       PWDATA;
  wire [STRB_WIDTH-1:0]       PSTRB;

  // Instantiate APB Master
  apb4_master dut (
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .apb_write_paddr(apb_write_paddr),
    .apb_read_paddr(apb_read_paddr),
    .apb_write_data(apb_write_data),
    .READ_WRITE(READ_WRITE),
    .transfer(transfer),
    .IN_STRB(IN_STRB),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .apb_read_data_out(apb_read_data_out),
    .transfer_error(transfer_error),
    .error_status(error_status),
    .PSEL1(PSEL1),
    .PSEL2(PSEL2),
    .PENABLE(PENABLE),
    .PADDR(PADDR),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB)
  );

  // Bind assertions to the design
  // Design name    Design instance    verif comp name           vc instance (mapping)
  bind apb4_master:dut apb4_master_assertions assertions_bind (
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .current_state(current_state),
    .next_state(next_state),
    .PADDR(PADDR),
    .PWRITE(PWRITE),
    .PSEL1(PSEL1),
    .PSEL2(PSEL2),
    .PENABLE(PENABLE),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .transfer(transfer),
    .READ_WRITE(READ_WRITE),
    .PSTRB(PSTRB),
    .timeout_counter(timeout_counter),
    .transfer_error(transfer_error),
    .error_status(error_status)
  );

  // Clock generation
  initial begin
    PCLK = 0;
    forever #(CLK_PERIOD/2) PCLK = ~PCLK;
  end

  // Task for monitoring states
  task monitor_state;
    begin
      $display("Time=%0t: PSEL1=%b, PSEL2=%b, PENABLE=%b, PREADY=%b", 
               $time, PSEL1, PSEL2, PENABLE, PREADY);
      $display("Error Results - Error=%b, ErrorStatus=%h\n", transfer_error, error_status);
    end
  endtask

  task initialize();
    begin
      PRESETn         = 1;
      apb_write_paddr = 0;
      apb_read_paddr  = 0;
      apb_write_data  = 0;
      READ_WRITE      = 0;
      transfer        = 0;
      IN_STRB         = 4'h0;
      PRDATA          = 0;
      PREADY          = 0;
      PSLVERR         = 0;
    end
  endtask

  task reseting();
    begin
      $display("========== Resetting Phase ==========");
      PRESETn = 0;
      #50 PRESETn = 1;
    end
  endtask

  task test1;
    begin
      $display("\nTest Case 1: Write to Slave 1 (0x0000_0005) - NO WAIT");
      @(posedge PCLK);
      apb_write_paddr = 32'h0000_0005;
      apb_write_data  = 32'hA5A5_A5A5;
      IN_STRB         = 4'b1111;
      READ_WRITE      = 0;
      transfer        = 1;
      PREADY          = 0;
      monitor_state();
      
      $display("========== Setup Phase ==========");
      @(posedge PCLK);
      monitor_state();
      
      $display("========== Access Phase ==========");
      @(posedge PCLK);
      PREADY = 1;  // Slave is ready
      monitor_state();
      transfer = 0;
      
      @(posedge PCLK);
      PREADY = 0;
      $display("Write transfer completed");
      monitor_state();
    end
  endtask

  task test2;
    begin
      $display("\nTest Case 2: Write to Slave 1 with Timeout");
      @(posedge PCLK);
      apb_write_paddr = 32'h0000_0005;
      apb_write_data  = 32'hA5A5_A5A5;
      IN_STRB         = 4'b1111;
      READ_WRITE      = 0;
      transfer        = 1;
      PREADY          = 0;
      monitor_state();
      
      $display("========== Setup Phase ==========");
      @(posedge PCLK);
      monitor_state();
      
      $display("========== Access Phase with Timeout ==========");
      @(posedge PCLK);
      repeat(101) @(posedge PCLK);
      PREADY = 1;
      monitor_state();
      transfer = 0;
      
      @(posedge PCLK);
      PREADY = 0;
      $display("Write transfer completed");
      monitor_state();
    end
  endtask

  task test3;
    begin
      $display("\nTest Case 3: Read from Invalid Address");
      @(posedge PCLK);
      apb_write_paddr = 32'h0001_1000;
      apb_read_paddr  = 32'h0000_0022;
      READ_WRITE      = 1;
      transfer        = 1;
      PREADY          = 0;
      monitor_state();
      
      $display("========== Setup Phase ==========");
      @(posedge PCLK);
      monitor_state();
      
      $display("========== Access Phase ==========");
      @(posedge PCLK);
      repeat(101) @(posedge PCLK);
      PREADY = 1;
      PRDATA = 32'hFACE_FACE;
      monitor_state();
      transfer = 0;
      
      @(posedge PCLK);
      PREADY = 0;
      $display("Read transfer completed");
      monitor_state();
    end
  endtask

  // Main test stimulus
  initial begin
    // Initialize signals
    initialize();
    reseting();
    
    $display("========== IDLE Phase ==========");
    #50;
    
    // Run test cases
    test1();
    repeat(5) @(posedge PCLK);
    
    // Uncomment to run additional tests
    test2();
    repeat(5) @(posedge PCLK);
    test3();
    repeat(5) @(posedge PCLK);
    
    $display("Simulation completed successfully");
    monitor_state();
    $finish;
  end

  // Timeout watchdog
  initial begin
    #10000 // 10us timeout
    $display("Simulation timeout!");
    $finish;
  end

  // Waveform dumping
  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars;
  end

endmodule