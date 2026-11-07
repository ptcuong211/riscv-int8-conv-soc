// ============================================================================
// File: firmware/test_accelerator.c
// Description: Bare-metal C Firmware for PicoRV32 SoC with INT8 Conv Accelerator
// Target:      Stage 6 SoC Integration Verification
// ============================================================================

#include <stdint.h>

// ----------------------------------------------------------------------------
// Dinh nghia cac dia chi thanh ghi MMIO theo dung Memory Map Stage 6
// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// Ham nhat: Thuc thi kiem tra All Ones (Input = 1, Kernel = 1, Output = 9)
// ----------------------------------------------------------------------------
int test_all_ones(void) {
    int i;
    int err_count = 0;

    // 1. Nap 1024 pixel vao Input Buffer (toan bo gia tri = 1)
    for (i = 0; i < 1024; i++) {
        REG_IBUF_ADDR = (uint32_t)i;
        REG_IBUF_DATA = (uint32_t)1;
    }

    // 2. Nap 9 trong so vao Weight Buffer (toan bo gia tri = 1)
    for (i = 0; i < 9; i++) {
        REG_WBUF_ADDR = (uint32_t)i;
        REG_WBUF_DATA = (uint32_t)1;
    }

    // 3. Phat xung START qua MMIO CTRL
    REG_ACCEL_CTRL = 1;

    // 4. Polling cho den khi DONE xuat hien trong STATUS
    while ((REG_ACCEL_STATUS & STATUS_DONE_BIT) == 0) {
        // Cho accelerator tinh toan xong
    }

    // Xoa co sticky DONE
    REG_ACCEL_STATUS = STATUS_DONE_BIT;

    // 5. Doc va kiem tra toan bo 900 ket qua tu Output Buffer
    for (i = 0; i < 900; i++) {
        REG_OBUF_ADDR = (uint32_t)i;
        int32_t val = REG_OBUF_DATA;
        if (val != 9) {
            err_count++;
        }
    }

    return err_count;
}

// ----------------------------------------------------------------------------
// Ham main thuc thi chuong trinh tren PicoRV32
// ----------------------------------------------------------------------------
int main(void) {
    int errors;

    // Chay luot 1: All Ones Test
    errors = test_all_ones();
    if (errors != 0) {
        REG_DEBUG_OUT = 0xDEAD0000 | (errors & 0xFFFF);
        return -1;
    }

    // Luot 1 thanh cong: Bao ma tieu chuan PASS luot 1
    REG_DEBUG_OUT = 0xCAFE0001;

    // Chay luot 2: Re-run Test de xac minh chay lien tiep nhieu lan
    errors = test_all_ones();
    if (errors != 0) {
        REG_DEBUG_OUT = 0xDEAD0000 | (errors & 0xFFFF);
        return -2;
    }

    // Luot 2 thanh cong xuat sac: Bao ma tieu chuan PASS toan bo Stage 6
    REG_DEBUG_OUT = 0xCAFE0002;

    return 0;
}

