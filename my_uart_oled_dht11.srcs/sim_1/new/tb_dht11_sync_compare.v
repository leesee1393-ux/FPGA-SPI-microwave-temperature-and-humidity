
`timescale 1ns / 1ps

module tb_dht11_sync_compare;

    reg clk = 0;
    reg reset = 1;
    reg start = 0;
    reg sensor_low = 0;

    // 풀업이 있는 DHT11 DATA 라인 모델
    tri1 dht_data_a;
    tri1 dht_data_b;

    assign dht_data_a = sensor_low ? 1'b0 : 1'bz;
    assign dht_data_b = sensor_low ? 1'b0 : 1'bz;

    wire [15:0] temp_a, hum_a;
    wire [15:0] temp_b, hum_b;
    wire [7:0] checksum_a, checksum_b;
    wire valid_a, valid_b;
    wire input_a, input_b;

    integer valid_count_a = 0;
    integer valid_count_b = 0;
    integer errors = 0;
    integer i;

    // 100MHz
    always #5 clk = ~clk;

    // 정상 프레임: 습도 60.0%, 온도 25.0C
    localparam [39:0] GOOD_FRAME =
        {8'd60, 8'd0, 8'd25, 8'd0, 8'd85};

    // 체크섬만 잘못된 프레임
    localparam [39:0] BAD_FRAME =
        {8'd60, 8'd0, 8'd25, 8'd0, 8'd84};

    // 시뮬레이션 속도를 위해 호스트 START LOW만
    // 18ms -> 18us로 축소
    // 센서 응답 및 데이터 비트 타이밍은 실제 값 유지

    dht11 #(
        .LOW_18MS(1800),
        .USE_SYNC(1)
    ) dut_sync (
        .clk(clk),
        .reset(reset),
        .start(start),
        .io_mode(1'b1),
        .o_data(1'b0),
        .i_data(input_a),
        .dht11_data(dht_data_a),
        .humidity(hum_a),
        .temperature(temp_a),
        .checksum(checksum_a),
        .data_valid(valid_a)
    );

    dht11 #(
        .LOW_18MS(1800),
        .USE_SYNC(0)
    ) dut_raw (
        .clk(clk),
        .reset(reset),
        .start(start),
        .io_mode(1'b1),
        .o_data(1'b0),
        .i_data(input_b),
        .dht11_data(dht_data_b),
        .humidity(hum_b),
        .temperature(temp_b),
        .checksum(checksum_b),
        .data_valid(valid_b)
    );

    // data_valid 펄스 계수
    always @(posedge clk) begin
        if (reset) begin
            valid_count_a <= 0;
            valid_count_b <= 0;
        end
        else begin
            if (valid_a)
                valid_count_a <= valid_count_a + 1;

            if (valid_b)
                valid_count_b <= valid_count_b + 1;
        end
    end

    // 두 DUT와 Testbench 카운터 초기화
    task reset_duts;
        begin
            @(negedge clk);
            reset = 1;
            start = 0;
            sensor_low = 0;

            repeat (5) @(negedge clk);
            reset = 0;

            repeat (5) @(negedge clk);
        end
    endtask

    // HIGH 펄스 폭을 ns 단위로 지정
    task send_bit;
        input bit_value;
        input integer high_ns;
        begin
            sensor_low = 1;
            #50000;  // 50us LOW

            sensor_low = 0;

            if (high_ns > 0)
                #(high_ns);
            else if (bit_value)
                #70000;  // 1: 70us HIGH
            else
                #28000;  // 0: 28us HIGH
        end
    endtask

    // 40비트 전송
    // boundary_index: -1이면 정상 타이밍
    // 그 외에는 지정한 비트만 경계 타이밍 사용
    task send_frame;
        input [39:0] frame;
        input integer boundary_index;
        input integer boundary_high_ns;

        integer bit_index;
        begin
            sensor_low = 1;
            #80000;  // 응답 LOW 80us

            sensor_low = 0;
            #80000;  // 응답 HIGH 80us

            for (bit_index = 39;
                 bit_index >= 0;
                 bit_index = bit_index - 1) begin

                if (bit_index == boundary_index)
                    send_bit(frame[bit_index],
                             boundary_high_ns);
                else
                    send_bit(frame[bit_index], 0);
            end

            // 마지막 HIGH 펄스 종료
            sensor_low = 1;
            #50000;

            sensor_low = 0;
        end
    endtask

    // 한 번의 DHT11 트랜잭션 실행
    task run_transaction;
        input [39:0] frame;
        input integer boundary_index;
        input integer boundary_high_ns;

        begin
            // 두 DUT가 IDLE인지 확인
            wait(dut_sync.r_state == 0 &&
                 dut_raw.r_state == 0);

            @(negedge clk);
            start = 1;

            @(negedge clk);
            start = 0;

            // 두 DUT가 호스트 START LOW를
            // 완료하고 DATA를 해제할 때까지 대기
            wait(dut_sync.r_state == 2 &&
                 dut_raw.r_state == 2);

            // 호스트 해제 후 40us
            #40000;

            send_frame(frame,
                       boundary_index,
                       boundary_high_ns);

            // FSM이 DONE/VALID를 마칠 시간 확보
            #1000;

            wait(dut_sync.r_state == 0 &&
                 dut_raw.r_state == 0);

            repeat (5) @(negedge clk);
        end
    endtask

    // 공통 결과 출력
    task print_result;
        begin
            $display("SYNC ON : VALID=%0d DONE=%0d CHECK_FAIL=%0d TIMEOUT=%0d",
                valid_count_a,
                dut_sync.r_done_count,
                dut_sync.r_checksum_fail_count,
                dut_sync.r_timeout_count);

            $display("SYNC OFF: VALID=%0d DONE=%0d CHECK_FAIL=%0d TIMEOUT=%0d",
                valid_count_b,
                dut_raw.r_done_count,
                dut_raw.r_checksum_fail_count,
                dut_raw.r_timeout_count);
        end
    endtask

    // =====================================
    // TEST 1: 정상 프레임 100회 반복
    // =====================================
    task test_normal_100;
        begin
            $display("");
            $display("===== TEST 1: NORMAL 100 FRAMES =====");

            reset_duts();

            for (i = 0; i < 100; i = i + 1) begin
                run_transaction(GOOD_FRAME, -1, 0);

                if ((i + 1) % 10 == 0)
                    $display("Completed %0d / 100",
                             i + 1);
            end

            print_result();

            if (valid_count_a == 100 &&
                valid_count_b == 100 &&
                temp_a == 16'h1900 &&
                temp_b == 16'h1900 &&
                hum_a == 16'h3C00 &&
                hum_b == 16'h3C00 &&
                dut_sync.r_done_count == 100 &&
                dut_raw.r_done_count == 100 &&
                dut_sync.r_checksum_fail_count == 0 &&
                dut_raw.r_checksum_fail_count == 0 &&
                dut_sync.r_timeout_count == 0 &&
                dut_raw.r_timeout_count == 0)
                $display("TEST 1 PASS");
            else begin
                $display("TEST 1 FAIL");
                errors = errors + 1;
            end
        end
    endtask

    // =====================================
    // TEST 2: HIGH 펄스 경계 테스트
    // =====================================
    task test_boundary;
        input integer pulse_ns;
        input integer expected_bit;

        begin
            reset_duts();

            // 모두 0인 프레임의 첫 번째 비트만
            // 지정한 HIGH 폭으로 전송
            run_transaction(40'h0000000000,
                            39, pulse_ns);

            $display("");
            $display("HIGH PULSE = %0d ns", pulse_ns);

            $display("SYNC ON  : bit39=%b",
                     dut_sync.r_data[39]);

            $display("SYNC OFF : bit39=%b",
                     dut_raw.r_data[39]);

            print_result();

            // 50.0us는 경계 자체이므로
            // 판정값을 강제하지 않고 관찰만 함
            if (expected_bit == -1) begin
                $display("BOUNDARY OBSERVATION COMPLETE");
            end
            else if (dut_sync.r_data[39] === expected_bit[0] &&
                     dut_raw.r_data[39] === expected_bit[0] &&
                     dut_sync.r_done_count == 1 &&
                     dut_raw.r_done_count == 1 &&
                     dut_sync.r_timeout_count == 0 &&
                     dut_raw.r_timeout_count == 0) begin
                $display("BOUNDARY PASS");
            end
            else begin
                $display("BOUNDARY FAIL");
                errors = errors + 1;
            end
        end
    endtask

    // =====================================
    // TEST 3: 체크섬 오류 주입
    // =====================================
    task test_bad_checksum;
        begin
            $display("");
            $display("===== TEST 3: BAD CHECKSUM =====");

            reset_duts();

            run_transaction(BAD_FRAME, -1, 0);

            print_result();

            if (valid_count_a == 0 &&
                valid_count_b == 0 &&
                dut_sync.r_done_count == 1 &&
                dut_raw.r_done_count == 1 &&
                dut_sync.r_checksum_fail_count == 1 &&
                dut_raw.r_checksum_fail_count == 1 &&
                dut_sync.r_timeout_count == 0 &&
                dut_raw.r_timeout_count == 0)
                $display("TEST 3 PASS");
            else begin
                $display("TEST 3 FAIL");
                errors = errors + 1;
            end
        end
    endtask

    // =====================================
    // MAIN
    // =====================================
    initial begin
        $display("================================");
        $display("DHT11 EXTENDED A/B TEST");
        $display("================================");

        test_normal_100();

        $display("");
        $display("===== TEST 2: PULSE BOUNDARY =====");

        test_boundary(49900, 0);
        test_boundary(50000, -1);
        test_boundary(50100, 1);

        test_bad_checksum();

        $display("");
        $display("================================");

        if (errors == 0)
            $display("ALL TESTS PASS");
        else
            $display("TOTAL FAILED TESTS = %0d",
                     errors);

        $display("================================");

        $finish;
    end

    // 무한 대기 방지
    initial begin
        #1000000000;
        $display("FAIL: GLOBAL TEST TIMEOUT");
        $finish;
    end

endmodule
