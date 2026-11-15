// Every SMBus protocol (SMBus 3.3 6.5.1-6.5.8), without and with PEC: Quick
// Command (W, R), Send/Receive Byte, Write/Read Byte, Write/Read Word,
// Process Call, Block Write/Read (lengths 0, 5, 32), Block Write-Block Read
// Process Call. The scoreboard checks every answer and the host checks
// every PEC it receives. REQ-SMB-001..010.
class smbus_proto_test extends base_test;
    `uvm_component_utils(smbus_proto_test)

    function new(string name = "smbus_proto_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int p = 0; p < 2; p++) begin
            msg(SMB_QUICK_W);
            msg(SMB_RECV_BYTE, 8'h00, none, p);
            msg(SMB_QUICK_R);
            msg(SMB_RECV_BYTE, 8'h00, none, p);
            msg(SMB_SEND_BYTE, 8'h40, none, p);
            for (int r = 0; r < 8; r++) begin
                rand_bytes(d, 1);
                msg(SMB_WRITE_BYTE, 8'(r), d, p);
            end
            for (int r = 0; r < 8; r++) msg(SMB_READ_BYTE, 8'(r), none, p);
            for (int r = 0; r < 4; r++) begin
                rand_bytes(d, 2);
                msg(SMB_WRITE_WORD, 8'h10 + 8'(r), d, p);
                msg(SMB_READ_WORD, 8'h10 + 8'(r), none, p);
            end
            rand_bytes(d, 2);
            msg(SMB_PROC_CALL, 8'h20, d, p);
            for (int i = 0; i < 4; i++) begin
                rand_bytes(d, (i == 0) ? 5 : (i == 1) ? 0 : (i == 2) ? 32 : 1);
                msg(SMB_BLOCK_WRITE, 8'h30, d, p);
                msg(SMB_BLOCK_READ, 8'h30, none, p);
            end
            rand_bytes(d, 4);
            msg(SMB_BLOCK_PROC_CALL, 8'h31, d, p);
            rand_bytes(d, 0);
            msg(SMB_BLOCK_PROC_CALL, 8'h31, d, p);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : smbus_proto_test
