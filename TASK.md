# Codex 작업 지시서
## Basys3 FPGA — DHT11 + HC-SR04 + FND + UART 통합 및 검증

### 1. 작업 목표

기존 Vivado 2021.2 프로젝트에 HC-SR04 초음파 거리 센서를 통합한다.

**가장 중요한 조건은 기존 DHT11 온도·습도 측정 및 UART 출력 기능을 훼손하지 않는 것이다.**

기존 RTL을 최대한 재사용하고, 필요한 부분만 수정한다.

**개발 환경**
- FPGA: Digilent Basys3 (XC7A35T-1CPG236C)
- 클록: 100MHz
- HDL: Verilog
- 개발 도구: Vivado 2021.2
- UART: 9600bps
- 기존 센서: DHT11
- 신규 센서: HC-SR04

작업 폴더:
`D:\project\FPGA\ai2\my_uart_oled_dht11`

참고 코드:
`basys3_hcsr04_integration` 폴더에 있는 수정된 Verilog 파일

참고 폴더가 존재하지 않으면 기존 프로젝트의 파일을 기준으로 직접 수정한다.

---

### 2. 작업 전 필수 사항

1. 프로젝트의 RTL 소스, XDC, Testbench, 모듈 간 의존 관계를 분석한다.
2. 기존 동작 버전을 백업한다.
3. 기존 `top.v`, UART, DHT11, FND 구조를 확인한다.
4. 기존 RTL과 통합 코드의 차이를 비교한다.
5. 이미 정상 동작하는 기능은 불필요하게 수정하지 않는다.
6. 기존 파일을 무조건 삭제하지 말고 중복 여부와 의존성을 확인한다.
7. 실제 파일 내용을 확인하지 않고 모듈 포트나 신호 이름을 추정하지 않는다.

기존 `data_sender.v`가 COUNTER 문자열 전송용이라면 센서 데이터 송신용 모듈과 구분한다.

기존 `uart_tx.v`, `uart_rx.v`는 재사용한다.

---

### 3. 주요 RTL 수정 범위

| 파일 | 작업 내용 |
|---|---|
| `top.v` | HC-SR04 거리 데이터를 FND 및 UART로 전달 |
| `dht11_fnd_controller.v` | SW2 거리 표시 모드 추가 |
| `fnd_controller.v` | 거리 모드에서 소수점 OFF |
| `uart_system.v` | 거리 데이터와 유효 신호 입력 추가 |
| `uart_controller.v` | 거리 데이터 송신 모듈 연결 |
| `sensor_data_sender.v` | 온도·습도·거리 ASCII 메시지 송신 |
| `hcsr04_controller.v` | HC-SR04 거리 측정 FSM |
| `.xdc` | DHT11 및 HC-SR04 PMOD 핀 할당 검증 |

기존 `dht11.v`, `tick_generator.v`, `uart_tx.v`, `uart_rx.v`, `uart_fifo.v` 등은 가능한 한 유지한다.

단, 실제 모듈 연결 구조상 수정이 필요한 경우에는 이유를 기록하고 최소한으로 변경한다.

---

### 4. 스위치 동작 요구사항

기존 온도·습도 표시 기능에 거리 표시 기능을 추가한다.

| 조건 | FND 표시 |
|---|---|
| SW0 ON, SW1/SW2 OFF | 온도 |
| SW1 ON, SW2 OFF | 습도 |
| SW2 ON | 거리(cm) |
| 모든 스위치 OFF | 온도(기본값) |

스위치 우선순위:

**SW2(거리) > SW1(습도) > SW0(온도)**

예상 FND 출력:
- 온도: `25.00`
- 습도: `60.00`
- 거리: `0123`

거리 표시에서는 소수점을 OFF 처리한다.

FND의 기존 Digit Scan, BCD 변환 및 Tick Generator를 재사용한다.

거리 표시 범위는 0~9999cm를 지원할 수 있도록 설계하되, 센서의 유효 측정 범위를 초과한 값은 정상 측정으로 취급하지 않는다.

스위치 변경이 DHT11 측정 FSM이나 HC-SR04 측정 FSM에 영향을 주면 안 된다.

---

### 5. HC-SR04 컨트롤러 설계

`hcsr04_controller.v`를 구현하거나 기존 코드를 검토하여 수정한다.

**필수 기능**

1. 100MHz 기준 TRIG HIGH 10µs 생성
2. ECHO HIGH 펄스 폭 측정
3. 2단 플립플롭으로 ECHO 입력 동기화
4. ECHO 시간으로 거리(cm) 계산
5. 측정 완료 시 `data_valid`를 1클록 동안 발생
6. ECHO 응답이 없거나 과도하게 길면 타임아웃 처리
7. 반복 측정 시 최소 60ms의 측정 간격 확보
8. 타임아웃 이후 FSM이 다음 측정을 정상적으로 시작하도록 복구

권장 FSM:

`IDLE → TRIGGER → WAIT_ECHO → MEASURE → DONE/ERROR`

거리 계산 기준:

100MHz에서 약 5,800클록을 1cm로 환산한다.

계산 과정에서 비트 폭, 정수 나눗셈, 오버플로 및 합성 가능성을 확인한다.

---

### 6. UART 통합

기존 UART 송수신 로직을 재사용한다.

`uart_controller.v`에서 사용하는 모듈 이름이 실제 선언과 일치하는지 확인한다.

예를 들어 신규 모듈 선언이 다음과 같다면:

`module sensor_data_sender (...)`

상위 모듈에서도 반드시 `sensor_data_sender`로 인스턴스화한다.

**출력 형식**

```text
TEMP: 25.00
HUM : 60.00
DIST: 0123 cm
```

요구사항:

1. DHT11 온도·습도 UART 출력 유지
2. HC-SR04 거리 UART 출력 추가
3. 스위치 상태와 관계없이 UART 출력
4. 각 센서의 `data_valid` 신호를 올바르게 처리
5. UART TX의 `tx_busy` 및 `tx_start` 핸드셰이크 검증
6. 온도·습도·거리 데이터가 전송 도중 변경되어 메시지가 섞이지 않도록 데이터 래칭
7. 센서 측정 완료 신호가 UART 전송 중 발생해도 최신 값이 보존되도록 처리
8. UART 출력 주기를 과도하게 높이지 않도록 제어

권장 출력 정책:
- DHT11: 신규 정상 측정값 수신 시 온도·습도 출력
- HC-SR04: 최신 측정값을 저장하고 약 1초 주기로 거리 출력

기존 UART FIFO가 있다면 활용 가능성을 검토한다. 불필요한 UART TX 모듈 중복 구현은 금지한다.

---

### 7. Basys3 센서 핀 연결

기존 DHT11 연결을 유지한다.

| 장치 | PMOD | FPGA PACKAGE_PIN |
|---|---|---|
| DHT11 DATA | JA1 | J1 |
| HC-SR04 TRIG | JA3 | J2 |
| HC-SR04 ECHO | JA4 | G2 |

XDC 설정:

```tcl
set_property PACKAGE_PIN J1 [get_ports dht11_data]
set_property IOSTANDARD LVCMOS33 [get_ports dht11_data]

set_property PACKAGE_PIN J2 [get_ports hcsr04_trig]
set_property IOSTANDARD LVCMOS33 [get_ports hcsr04_trig]

set_property PACKAGE_PIN G2 [get_ports hcsr04_echo]
set_property IOSTANDARD LVCMOS33 [get_ports hcsr04_echo]
```

기존 핀 할당과 중복되지 않는지 확인한다.

**하드웨어 안전 요구사항**

- HC-SR04의 일반적인 ECHO 출력은 5V이므로 Basys3에 직접 연결하지 않는다.
- 2.2kΩ/3.3kΩ 저항 전압 분배기 또는 적합한 레벨 시프터를 사용한다.
- HC-SR04는 사양에 맞는 5V 전원을 공급한다.
- FPGA와 센서의 GND를 공통으로 연결한다.
- RTL이나 XDC를 수정했다고 실제 5V 입력이 안전해지는 것은 아니므로, 배선 안전 사항을 별도로 문서화한다.

---


### 8. Vivado 오류 및 통합 검증

모든 RTL 소스에 대해 다음 항목을 확인한다.

- 중복 모듈 선언
- 누락된 하위 모듈
- 포트 이름 불일치
- 포트 비트 폭 불일치
- 선언되지 않은 wire/reg
- Multiple Driver
- Latch 발생 여부
- FSM 상태 전이
- XDC 핀 충돌
- UART 송신 충돌
- 기존 ILA 디버그 코어 잔존 여부

`get_debug_cores`와 Implementation 결과를 확인하여 불필요한 ILA 관련 오류가 발생하지 않도록 한다.

**검증 환경이 제공되는 경우**
1. Verilog 문법 검사
2. XSim Behavioral Simulation
3. Run Synthesis
4. Run Implementation
5. Generate Bitstream

Vivado 실행이 불가능한 환경에서는 실제 실행한 검사와 실행하지 못한 검사를 명확히 구분하여 보고한다.

빌드 또는 테스트를 수행하지 않았는데 PASS라고 보고하지 않는다.

---

### 10. 최종 작업 보고서

작업 완료 후 다음 형식으로 보고한다.

**A. 수정 파일 목록**

파일별 변경 전/후 핵심 내용 정리

**B. 유지된 기존 기능**

DHT11, UART, FND, 기존 하위 모듈 동작 확인

**C. 신규 기능**

HC-SR04 거리 측정, SW2 FND 거리 표시, UART 거리 출력

**D. 테스트 결과**

각 Testbench의 PASS/FAIL 및 실제 실행 로그

**E. 합성 및 구현 결과**

Synthesis, Implementation, Bitstream 생성 성공 여부

**F. 남은 문제**

미해결 오류, 경고, 하드웨어 실측이 필요한 항목

**G. 회귀 검증**

기존 기능이 변경 전과 동일하게 동작하는지 비교

---

### 11. 최종 작업 원칙

- 기존 정상 동작 기능을 훼손하지 않는다.
- 기존 모듈을 최대한 재사용한다.
- 불필요한 신규 모듈 생성을 최소화한다.
- 중복된 `data_sender` 등의 파일은 의존성을 확인한 뒤 정리한다.
- Verilog-2001 및 Vivado 2021.2 호환성을 유지한다.
- 가능하면 수정 전/후 Diff를 제공한다.
- 검증되지 않은 성공을 주장하지 않는다.
- 문제가 발생하면 근본 원인을 분석하고 수정한다.

**최종 목표: Basys