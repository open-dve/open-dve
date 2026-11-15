// n messages drawn by odve_smbus_item::user_randomize(): every protocol the
// command lists allow, random data and block lengths, PEC on p_pec %.
// set_from_tab() fills the command lists from a cfg's cmd_tab.
class odve_smbus_rand_seq extends uvm_sequence #(odve_smbus_item);
    `uvm_object_utils(odve_smbus_rand_seq)

    int unsigned n        = 20;
    bit [6:0]    tgt_addr = 7'h3A;
    int unsigned p_pec    = 50;
    int unsigned max_blk  = 32;
    int unsigned w_proto[] = '{1, 1, 2, 2, 3, 3, 3, 3, 2, 3, 3, 2, 0, 0};
    bit [7:0]    cmds_send[$], cmds_byte[$], cmds_word[$], cmds_pcall[$], cmds_block[$], cmds_bpcall[$];
    odve_rand    rng;

    function new(string name = "odve_smbus_rand_seq");
        super.new(name);
    endfunction

    function void set_from_tab(odve_smbus_cmd_e tab[256]);
        foreach (tab[c]) begin
            case (tab[c])
                SMB_CMD_SEND:   cmds_send.push_back(8'(c));
                SMB_CMD_BYTE:   cmds_byte.push_back(8'(c));
                SMB_CMD_WORD:   cmds_word.push_back(8'(c));
                SMB_CMD_PCALL:  cmds_pcall.push_back(8'(c));
                SMB_CMD_BLOCK:  cmds_block.push_back(8'(c));
                SMB_CMD_BPCALL: cmds_bpcall.push_back(8'(c));
                default: ;
            endcase
        end
    endfunction

    virtual task body();
        odve_smbus_item item;
        if (rng == null) rng = new(get_full_name());
        repeat (n) begin
            item = odve_smbus_item::type_id::create("item");
            item.rng         = rng.spawn();
            item.tgt_addr    = tgt_addr;
            item.p_pec       = p_pec;
            item.max_blk     = max_blk;
            item.w_proto     = w_proto;
            item.cmds_send   = cmds_send;
            item.cmds_byte   = cmds_byte;
            item.cmds_word   = cmds_word;
            item.cmds_pcall  = cmds_pcall;
            item.cmds_block  = cmds_block;
            item.cmds_bpcall = cmds_bpcall;
            `odve_rand(item)
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
