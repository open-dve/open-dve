// One UART character (or line event) on one direction of the link.
//
// Stimulus (master driver / slave response): kind, data, idle_bits before
// the frame and the error injections bad_parity / bad_stop, the break length
// brk_bits, the glitch length glitch_clks. The frame format (data bits,
// parity, stop bits, bit period) is a property of the link and lives in
// odve_uart_cfg; the monitor copies it into the observed item.
//
// Observed (monitor): dir, format, pe / fe / brk, gap_bits, t_end.
//
// No `rand`/constraints (comp/agents/README.md): user_randomize() draws
// every value from the odve_rand stream `rng`, which the sequence hands in
// (comp/common/rand/README); reached through `odve_rand(item).
class odve_uart_item extends uvm_sequence_item;
    `uvm_object_utils(odve_uart_item)

    odve_uart_kind_e   kind        = ODVE_UART_DATA;
    bit [7:0]          data;
    int unsigned       idle_bits   = 0;     // mark time before the start bit, in bit times
    bit                bad_parity  = 0;     // inject: send the wrong parity bit
    bit                bad_stop    = 0;     // inject: first stop bit sent as space (framing error)
    int unsigned       brk_bits    = 0;     // BREAK: line held at space this many bit times
    int unsigned       glitch_clks = 0;     // GLITCH: a space pulse this many clocks long (false start bit)

    // format of the observed frame (monitor)
    int unsigned       data_bits   = 8;
    odve_uart_parity_e parity      = ODVE_UART_PAR_NONE;
    odve_uart_stop_e   stop        = ODVE_UART_STOP1;

    // observation (monitor)
    odve_uart_dir_e    dir         = ODVE_UART_TX;
    bit                pe          = 0;     // parity error
    bit                fe          = 0;     // framing error: first stop bit was space
    bit                brk         = 0;     // break: start, data, parity and stop all space
    int unsigned       gap_bits    = 0;     // whole bit times of mark since the previous frame ended
    time               t_end       = 0;     // time of the first stop bit's sample point

    // knobs of user_randomize()
    odve_rand          rng;
    int unsigned       gap_pct     = 30;    // chance of an idle gap before the frame
    int unsigned       max_idle    = 4;     // longest gap, bit times
    int unsigned       err_pct     = 0;     // chance of an error event instead of a good frame
    int unsigned       err_w[];             // weights: bad parity, bad stop, break, glitch
    int unsigned       bit_clks    = 32;    // for the glitch length (less than half a bit)

    function new(string name = "odve_uart_item");
        super.new(name);
        err_w = '{1, 1, 1, 1};
    endfunction

    function void user_randomize();
        int unsigned e;
        if (rng == null) rng = new(get_full_name());
        kind       = ODVE_UART_DATA;
        bad_parity = 0;
        bad_stop   = 0;
        data       = 8'(rng.u16()) & odve_uart_mask(data_bits);
        idle_bits  = 0;
        if (rng.chance(gap_pct)) idle_bits = rng.urand(1, max_idle);
        if (err_pct != 0 && rng.chance(err_pct)) begin
            e = rng.weighted(err_w);
            if (e == 0 && parity == ODVE_UART_PAR_NONE) e = 1;   // no parity bit to corrupt
            case (e)
                0: bad_parity = 1;
                1: begin
                       bad_stop = 1;
                       // an all-space character with a bad stop bit is a break, not a framing error
                       if (data == 0) data = 1;
                   end
                2: begin
                       kind     = ODVE_UART_BREAK;
                       brk_bits = rng.urand(14, 24);     // longer than the longest frame (12 bits)
                   end
                default: begin
                       kind        = ODVE_UART_GLITCH;
                       glitch_clks = rng.urand(1, bit_clks / 4);
                   end
            endcase
            if (idle_bits == 0) idle_bits = 1;   // a receiver resynchronises on mark after an error
        end
    endfunction

    function string fmt2string();
        string p;
        case (parity)
            ODVE_UART_PAR_NONE:  p = "N";
            ODVE_UART_PAR_EVEN:  p = "E";
            ODVE_UART_PAR_ODD:   p = "O";
            ODVE_UART_PAR_MARK:  p = "M";
            default:             p = "S";
        endcase
        return $sformatf("%0d%s%s", data_bits, p, stop == ODVE_UART_STOP1 ? "1" : stop == ODVE_UART_STOP1_5 ? "1.5" : "2");
    endfunction

    function string convert2string();
        return $sformatf("%s %s %s data=0x%02h%s%s%s%s%s gap=%0d", dir.name(), kind.name(), fmt2string(), data,
                         bad_parity ? " INJ_PAR" : "", bad_stop ? " INJ_STOP" : "",
                         pe ? " PE" : "", fe ? " FE" : "", brk ? $sformatf(" BRK(%0d bits)", brk_bits) : "", gap_bits);
    endfunction
endclass
