// The command set on page 0 and 1, without and with PEC: PMBUS_REVISION,
// CAPABILITY, VOUT_MODE; OPERATION on/off and the OFF bit of STATUS_BYTE /
// STATUS_WORD; ON_OFF_CONFIG; VOUT_COMMAND in ULINEAR16 and READ_VOUT;
// READ_IOUT in LINEAR11, decoded to amperes; the format helpers on their
// own. REQ-PMB-001..009.
class pmbus_basic_test extends base_test;
    `uvm_component_utils(pmbus_basic_test)

    function new(string name = "pmbus_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    function void chk_real(string what, real got, real exp, real tol);
        if (got < exp - tol || got > exp + tol) `uvm_error(get_name(), $sformatf("%s = %0f, expected %0f", what, got, exp))
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_pmbus_item p;
        bit [15:0] v;
        super.run_phase(phase);
        phase.raise_objection(this);
        // the data formats alone (Part II 7.3, 8.4.1)
        chk_real("LINEAR11 F00Ah", odve_pmbus_lin11_to_real(16'hF00A), 2.5, 0.0);
        chk_real("LINEAR11 0BE8h", odve_pmbus_lin11_to_real(16'h0BE8), 1000.0 * 2.0, 0.0);
        chk_real("LINEAR11 DFFFh", odve_pmbus_lin11_to_real(16'hDFFF), -1.0 / 32.0, 0.0);
        if (odve_pmbus_real_to_lin11(2.5, -2) != 16'hF00A) `uvm_error(get_name(), "LINEAR11 encode of 2.5 A")
        chk_real("ULINEAR16 0200h", odve_pmbus_ulin16_to_real(16'h0200, 5'h17), 1.0, 0.0);
        if (odve_pmbus_real_to_ulin16(1.2, 5'h17) != 16'h0266) `uvm_error(get_name(), "ULINEAR16 encode of 1.2 V")

        for (int pec = 0; pec < 2; pec++) begin
            expect_val(PMB_PMBUS_REVISION, 16'h0033, pec);
            expect_val(PMB_CAPABILITY, 16'h0090, pec);
            expect_val(PMB_VOUT_MODE, 16'h0017, pec);
            for (int pg = 1; pg >= 0; pg--) begin
                wr_byte(PMB_PAGE, 8'(pg), pec);
                expect_val(PMB_PAGE, 16'(pg), pec);
                expect_val(PMB_STATUS_BYTE, 16'h0040, pec);             // OFF
                expect_val(PMB_READ_VOUT, 16'h0000, pec);
                wr_word(PMB_VOUT_COMMAND, odve_pmbus_real_to_ulin16(pg ? 1.8 : 1.2, 5'h17), pec);
                rd(PMB_VOUT_COMMAND, p, pec);
                chk_real("VOUT_COMMAND", p.value, pg ? 1.8 : 1.2, 1.0 / 512.0);
                wr_byte(PMB_OPERATION, 8'h88, pec);                     // on
                expect_val(PMB_OPERATION, 16'h0088, pec);
                expect_val(PMB_STATUS_BYTE, 16'h0000, pec);
                expect_val(PMB_STATUS_WORD, 16'h0000, pec);
                rd(PMB_READ_VOUT, p, pec);
                chk_real("READ_VOUT", p.value, pg ? 1.8 : 1.2, 1.0 / 512.0);
                rd(PMB_READ_IOUT, p, pec);
                chk_real("READ_IOUT", p.value, pg ? 1.25 : 2.5, 0.0);
                wr_byte(PMB_OPERATION, 8'h08, pec);                     // off
                expect_val(PMB_STATUS_WORD, 16'h0840, pec);             // PG_STATUS#, OFF
                rd(PMB_READ_IOUT, p, pec);
                chk_real("READ_IOUT (off)", p.value, 0.0, 0.0);
                wr_byte(PMB_ON_OFF_CONFIG, 8'h00, pec);                 // always on
                expect_val(PMB_STATUS_BYTE, 16'h0000, pec);
                expect_val(PMB_ON_OFF_CONFIG, 16'h0000, pec);
                wr_byte(PMB_ON_OFF_CONFIG, 8'h18, pec);
            end
            expect_val(PMB_STATUS_CML, 16'h0000, pec);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : pmbus_basic_test
