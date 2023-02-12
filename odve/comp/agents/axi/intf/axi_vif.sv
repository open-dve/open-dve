interface axi_if #(
  parameter int unsigned ADDR_W = 0,
  parameter int unsigned DATA_W = 0,
  parameter int unsigned ID_W   = 0,
  parameter int unsigned USER_W = 0
);

  localparam int unsigned STRB_W = AXI_DATA_WIDTH / 8;

  typedef logic [ID_WIDTH-1:0]   ID_T;
  typedef logic [ADDR_WIDTH-1:0] ADDR_T;
  typedef logic [DATA_WIDTH-1:0] DATA_T;
  typedef logic [STRB_WIDTH-1:0] STRB_T;
  typedef logic [USER_WIDTH-1:0] USER_T;
//ADDR WRITE channel
  id_t              aw_id;
  addr_t            aw_addr;
  axi_pkg::len_t    aw_len;
  axi_pkg::size_t   aw_size;
  axi_pkg::burst_t  aw_burst;
  logic             aw_lock;
  axi_pkg::cache_t  aw_cache;
  axi_pkg::prot_t   aw_prot;
  axi_pkg::qos_t    aw_qos;
  axi_pkg::region_t aw_region;
  axi_pkg::atop_t   aw_atop;
  user_t            aw_user;
  logic             aw_valid;
  logic             aw_ready;
//DATA WITE CAHNNEL
  data_t            w_data;
  strb_t            w_strb;
  logic             w_last;
  user_t            w_user;
  logic             w_valid;
  logic             w_ready;

  id_t              b_id;
  axi_pkg::resp_t   b_resp;
  user_t            b_user;
  logic             b_valid;
  logic             b_ready;

//ADDR READ CHANNEL
  id_t              ar_id;
  addr_t            ar_addr;
  axi_pkg::len_t    ar_len;
  axi_pkg::size_t   ar_size;
  axi_pkg::burst_t  ar_burst;
  logic             ar_lock;
  axi_pkg::cache_t  ar_cache;
  axi_pkg::prot_t   ar_prot;
  axi_pkg::qos_t    ar_qos;
  axi_pkg::region_t ar_region;
  user_t            ar_user;
  logic             ar_valid;
  logic             ar_ready;
//ADD READ DATA CHANNEL

  id_t              r_id;
  data_t            r_data;
  axi_pkg::resp_t   r_resp;
  logic             r_last;
  user_t            r_user;
  logic             r_valid;
  logic             r_ready;

endinterface