// PAGE (Part II 11.10): OPERATION, ON_OFF_CONFIG and VOUT_COMMAND are kept
// per page and READ_VOUT / READ_IOUT / STATUS follow the selected page; a
// PAGE value the device does not have (2, FFh) is invalid data (CML bit 6,
// SMBALERT#) and leaves the page unchanged. REQ-PMB-004, 010, 013.
class pmbus_page_test extends base_test;
    `uvm_component_utils(pmbus_page_test)

    function new(string name = "pmbus_page_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        bit [15:0] v0, v1;
        super.run_phase(phase);
        phase.raise_objection(this);
        v0 = 16'(rng.urand(16'h0100, 16'h0400));
        v1 = 16'(rng.urand(16'h0100, 16'h0400));
        wr_byte(PMB_PAGE, 8'h00);  wr_word(PMB_VOUT_COMMAND, v0);  wr_byte(PMB_OPERATION, 8'h88);
        wr_byte(PMB_PAGE, 8'h01);  wr_word(PMB_VOUT_COMMAND, v1);  wr_byte(PMB_OPERATION, 8'h08);
        expect_val(PMB_READ_VOUT, 16'h0000);
        expect_val(PMB_STATUS_BYTE, 16'h0040);
        wr_byte(PMB_PAGE, 8'h00);
        expect_val(PMB_READ_VOUT, v0);
        expect_val(PMB_READ_IOUT, 16'hF00A);
        expect_val(PMB_OPERATION, 16'h0088);
        wr_byte(PMB_PAGE, 8'h01);
        expect_val(PMB_VOUT_COMMAND, v1);
        wr_byte(PMB_ON_OFF_CONFIG, 8'h10, 1);        // page 1: on whenever powered (bit 3 = 0)
        expect_val(PMB_READ_VOUT, v1, 1);
        expect_val(PMB_READ_IOUT, 16'hF005, 1);
        wr_byte(PMB_PAGE, 8'h02);                    // no such page
        expect_val(PMB_PAGE, 16'h0001);
        expect_val(PMB_STATUS_CML, 16'h0040);
        settle();
        if (!alert_line()) `uvm_error(get_name(), "SMBALERT# not asserted for an invalid PAGE")
        send_byte(PMB_CLEAR_FAULTS);
        wr_byte(PMB_PAGE, 8'hFF, 1);                 // all pages: not supported here
        expect_val(PMB_PAGE, 16'h0001);
        expect_val(PMB_STATUS_BYTE, 16'h0002);       // CML
        send_byte(PMB_CLEAR_FAULTS, 1);
        settle();
        if (alert_line()) `uvm_error(get_name(), "SMBALERT# still asserted after CLEAR_FAULTS")
        wr_byte(PMB_PAGE, 8'h00);
        expect_val(PMB_VOUT_COMMAND, v0);
        phase.drop_objection(this);
    endtask : run_phase
endclass : pmbus_page_test
