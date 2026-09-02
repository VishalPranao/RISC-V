module rv32_lsu (
    // Address calculated by the ALU
    input  logic [31:0]            address,

    // rs2 value for store instructions
    input  logic [31:0]            store_data,

    // Aligned 32-bit word returned by memory
    input  logic [31:0]            memory_read_data,

    // Decoder control signals
    input  logic                   mem_read,
    input  logic                   mem_write,
    input  rv32_pkg::mem_size_e    mem_size,
    input  logic                   load_unsigned,

    // Signals sent to memory
    output logic [31:0]            memory_address,
    output logic [31:0]            memory_write_data,
    output logic [3:0]             memory_write_strobe,
    output logic                   memory_read_enable,
    output logic                   memory_write_enable,

    // Formatted value sent toward writeback
    output logic [31:0]            load_data,

    // Indicates unsupported unaligned access
    output logic                   misaligned_access
);

    import rv32_pkg::*;

    logic [7:0]  selected_byte;
    logic [15:0] selected_halfword;

    always_comb begin
        // Default values
        memory_address      = address;
        memory_write_data   = 32'b0;
        memory_write_strobe = 4'b0000;

        memory_read_enable  = 1'b0;
        memory_write_enable = 1'b0;

        selected_byte       = 8'b0;
        selected_halfword   = 16'b0;
        load_data           = 32'b0;

        misaligned_access   = 1'b0;

        case (mem_size)

            //==========================================================
            // Byte access: LB, LBU or SB
            //==========================================================
            MEM_BYTE: begin
                // Select a byte from the 32-bit word returned by memory
                case (address[1:0])
                    2'b00: selected_byte = memory_read_data[7:0];
                    2'b01: selected_byte = memory_read_data[15:8];
                    2'b10: selected_byte = memory_read_data[23:16];
                    2'b11: selected_byte = memory_read_data[31:24];
                    default: selected_byte = 8'b0;
                endcase

                // Format LB/LBU result
                if (load_unsigned) begin
                    load_data = {
                        24'b0,
                        selected_byte
                    };
                end
                else begin
                    load_data = {
                        {24{selected_byte[7]}},
                        selected_byte
                    };
                end

                // Position SB data and produce its byte strobe
                case (address[1:0])
                    2'b00: begin
                        memory_write_data =
                            {24'b0, store_data[7:0]};

                        memory_write_strobe = 4'b0001;
                    end

                    2'b01: begin
                        memory_write_data =
                            {16'b0, store_data[7:0], 8'b0};

                        memory_write_strobe = 4'b0010;
                    end

                    2'b10: begin
                        memory_write_data =
                            {8'b0, store_data[7:0], 16'b0};

                        memory_write_strobe = 4'b0100;
                    end

                    2'b11: begin
                        memory_write_data =
                            {store_data[7:0], 24'b0};

                        memory_write_strobe = 4'b1000;
                    end

                    default: begin
                        memory_write_data   = 32'b0;
                        memory_write_strobe = 4'b0000;
                    end
                endcase

                // Byte accesses are always naturally aligned
                misaligned_access = 1'b0;
            end

            //==========================================================
            // Halfword access: LH, LHU or SH
            //==========================================================
            MEM_HALF: begin
                /*
                 * Valid halfword offsets are:
                 *
                 * address[1:0] = 00 → lower 16 bits
                 * address[1:0] = 10 → upper 16 bits
                 *
                 * 01 and 11 are misaligned.
                 */

                if (address[0] != 1'b0) begin
                    if (mem_read || mem_write)
                        misaligned_access = 1'b1;
                end
                else begin
                    if (address[1] == 1'b0) begin
                        selected_halfword =
                            memory_read_data[15:0];

                        memory_write_data =
                            {16'b0, store_data[15:0]};

                        memory_write_strobe = 4'b0011;
                    end
                    else begin
                        selected_halfword =
                            memory_read_data[31:16];

                        memory_write_data =
                            {store_data[15:0], 16'b0};

                        memory_write_strobe = 4'b1100;
                    end
                end

                // Format LH/LHU result
                if (load_unsigned) begin
                    load_data = {
                        16'b0,
                        selected_halfword
                    };
                end
                else begin
                    load_data = {
                        {16{selected_halfword[15]}},
                        selected_halfword
                    };
                end
            end

            //==========================================================
            // Word access: LW or SW
            //==========================================================
            MEM_WORD: begin
                /*
                 * A 32-bit word must start at an address divisible by 4.
                 * Therefore address[1:0] must equal 00.
                 */

                if (address[1:0] != 2'b00) begin
                    if (mem_read || mem_write)
                        misaligned_access = 1'b1;
                end
                else begin
                    load_data           = memory_read_data;
                    memory_write_data   = store_data;
                    memory_write_strobe = 4'b1111;
                end
            end

            default: begin
                load_data             = 32'b0;
                memory_write_data     = 32'b0;
                memory_write_strobe   = 4'b0000;
                misaligned_access     = mem_read || mem_write;
            end

        endcase

        // Enable memory only when the address is valid
        memory_read_enable =
            mem_read && !misaligned_access;

        memory_write_enable =
            mem_write && !misaligned_access;

        // Strobed writes are meaningful only for store instructions
        if (!memory_write_enable) begin
            memory_write_data   = 32'b0;
            memory_write_strobe = 4'b0000;
        end

        // Load data is meaningful only for load instructions
        if (!memory_read_enable) begin
            load_data = 32'b0;
        end
    end

endmodule