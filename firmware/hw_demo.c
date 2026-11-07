// ============================================================================
// File: firmware/hw_demo.c
// Description: Hardware Demo Bare-metal C Firmware for FPGA Board Bring-Up
// Target:      Stage 7 FPGA Hardware Demo (Digilent Basys 3)
// ============================================================================

#include <stdint.h>

#define MMIO_BASE           0x10000000
#define REG_ACCEL_CTRL      (*(volatile uint32_t *)(MMIO_BASE + 0x00))
#define REG_ACCEL_STATUS    (*(volatile uint32_t *)(MMIO_BASE + 0x04))
#define REG_IBUF_ADDR       (*(volatile uint32_t *)(MMIO_BASE + 0x08))
#define REG_IBUF_DATA       (*(volatile uint32_t *)(MMIO_BASE + 0x0C))
#define REG_WBUF_ADDR       (*(volatile uint32_t *)(MMIO_BASE + 0x10))
#define REG_WBUF_DATA       (*(volatile uint32_t *)(MMIO_BASE + 0x14))
#define REG_OBUF_ADDR       (*(volatile uint32_t *)(MMIO_BASE + 0x18))
#define REG_OBUF_DATA       (*(volatile int32_t  *)(MMIO_BASE + 0x1C))

#define REG_DEBUG_OUT       (*(volatile uint32_t *)(0x20000000))

#define STATUS_BUSY_BIT     (1 << 0)
#define STATUS_DONE_BIT     (1 << 1)

// Ham chay 1 luot tich chap va kiem tra
int run_conv_test(int pixel_val, int weight_val, int expected_val) {
    int i;
    int errors = 0;

    // 1. Nap 1024 pixel
    for (i = 0; i < 1024; i++) {
        REG_IBUF_ADDR = (uint32_t)i;
        REG_IBUF_DATA = (uint32_t)pixel_val;
    }

    // 2. Nap 9 weights
    for (i = 0; i < 9; i++) {
        REG_WBUF_ADDR = (uint32_t)i;
        REG_WBUF_DATA = (uint32_t)weight_val;
    }

    // 3. Phat xung START
    REG_ACCEL_CTRL = 1;

    // 4. Polling DONE
    while ((REG_ACCEL_STATUS & STATUS_DONE_BIT) == 0) {
        // Cho accelerator tinh toan xong
    }

    // Clear co DONE (W1C)
    REG_ACCEL_STATUS = STATUS_DONE_BIT;

    // 5. Doc va so sanh 900 ket qua tu Output Buffer
    for (i = 0; i < 900; i++) {
        REG_OBUF_ADDR = (uint32_t)i;
        int32_t res = REG_OBUF_DATA;
        if (res != expected_val) {
            errors++;
        }
    }

    return errors;
}

int main(void) {
    int err;

    // RUN 1: All Ones (Input = 1, Kernel = 1, Expected = 9)
    err = run_conv_test(1, 1, 9);
    if (err != 0) {
        REG_DEBUG_OUT = 0xDEAD0001;
        while (1);
    }
    REG_DEBUG_OUT = 0xCAFE0001; // PASS Run 1

    // RUN 2: Re-run voi bo du lieu moi (Input = 2, Kernel = 1, Expected = 18)
    err = run_conv_test(2, 1, 18);
    if (err != 0) {
        REG_DEBUG_OUT = 0xDEAD0002;
        while (1);
    }
    REG_DEBUG_OUT = 0xCAFE0002; // PASS Run 2 (ALL PASS)

    while (1) {
        // Treo an toan tai trang thai hoan tat
    }

    return 0;
}

