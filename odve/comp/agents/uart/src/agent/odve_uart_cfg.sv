// Configuration of one UART agent. The frame format and bit period are the
// link's: master, slave and DUT must agree (the env copies one into the
// others, vrf/tb/env/env.sv set_format()).
class odve_uart_cfg extends uvm_object;
    `uvm_object_utils(odve_uart_cfg)

    odve_uart_role_e     role     = ODVE_UART_MASTER;
    odve_uart_slv_mode_e slv_mode = ODVE_UART_SLV_MEM;   // slave role only
    bit                  has_mon  = 1;                    // one monitor per link: it watches both lines
    virtual odve_uart_if vif;

    // frame format (16550 LCR bits 0..5)
    int unsigned         data_bits = 8;                   // 5..8
    odve_uart_parity_e   parity    = ODVE_UART_PAR_NONE;
    odve_uart_stop_e     stop      = ODVE_UART_STOP1;

    // timing, in clk cycles: bit_clks is the nominal bit period every
    // receiver (monitor, slave) samples with - 16x oversampling, so a
    // multiple of 16. tx_bit_clks != 0 makes this agent's transmitter run at
    // another rate (baud mismatch).
    int unsigned         bit_clks    = 32;
    int unsigned         tx_bit_clks = 0;

    bit                  flow_ctrl = 0;   // RTS/CTS: transmit only while cts_n is low; slave drives s_cts_n from its FIFO level

    // monitor: frames with a parity/framing error or a break on txd are
    // expected (injected by the test) rather than protocol violations
    bit                  allow_tx_err = 0;

    // slave: the receive FIFO it models
    int unsigned         fifo_depth = 8;

    function new(string name = "odve_uart_cfg");
        super.new(name);
    endfunction

    function int unsigned tx_bit();
        return tx_bit_clks != 0 ? tx_bit_clks : bit_clks;
    endfunction

    // stop-bit time for a bit period of bc clocks
    function int unsigned stop_clks(int unsigned bc);
        case (stop)
            ODVE_UART_STOP1_5: return (bc * 3) / 2;
            ODVE_UART_STOP2:   return bc * 2;
            default:           return bc;
        endcase
    endfunction

    function void copy_format(odve_uart_cfg from);
        data_bits = from.data_bits;
        parity    = from.parity;
        stop      = from.stop;
        bit_clks  = from.bit_clks;
        flow_ctrl = from.flow_ctrl;
    endfunction

    function string fmt2string();
        string p;
        case (parity)
            ODVE_UART_PAR_NONE: p = "N";
            ODVE_UART_PAR_EVEN: p = "E";
            ODVE_UART_PAR_ODD:  p = "O";
            ODVE_UART_PAR_MARK: p = "M";
            default:            p = "S";
        endcase
        return $sformatf("%0d%s%s @%0d clk/bit%s", data_bits, p,
                         stop == ODVE_UART_STOP1 ? "1" : stop == ODVE_UART_STOP1_5 ? "1.5" : "2",
                         bit_clks, flow_ctrl ? " RTS/CTS" : "");
    endfunction
endclass
