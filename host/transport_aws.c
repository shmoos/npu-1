#include "transport.h"
#include <stdio.h>
#include <stdlib.h>

#ifdef AWS_FPGA
#include <fpga_pci.h>

typedef struct {
    pci_bar_handle_t bar_handle;
    int slot_id;
} aws_state_t;

static int aws_attach(npu_transport_t *t, int slot_id) {
    aws_state_t *st = (aws_state_t *)t->priv;
    st->slot_id = slot_id;
    int rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR0, 0, &st->bar_handle);
    if (rc != 0) {
        fprintf(stderr, "ERROR: fpga_pci_attach failed with code %d\n", rc);
        return rc;
    }
    return 0;
}

static void aws_detach(npu_transport_t *t) {
    aws_state_t *st = (aws_state_t *)t->priv;
    if (st->bar_handle >= 0) {
        fpga_pci_detach(st->bar_handle);
        st->bar_handle = -1;
    }
}

static int aws_poke(npu_transport_t *t, uint32_t addr, uint32_t data) {
    aws_state_t *st = (aws_state_t *)t->priv;
    return fpga_pci_poke(st->bar_handle, (uint64_t)addr, data);
}

static int aws_peek(npu_transport_t *t, uint32_t addr, uint32_t *data) {
    aws_state_t *st = (aws_state_t *)t->priv;
    return fpga_pci_peek(st->bar_handle, (uint64_t)addr, data);
}

npu_transport_t *npu_transport_create_aws(void) {
    npu_transport_t *t = (npu_transport_t *)malloc(sizeof(npu_transport_t));
    aws_state_t *st = (aws_state_t *)malloc(sizeof(aws_state_t));
    if (!t || !st) { free(t); free(st); return NULL; }
    st->bar_handle = -1;
    st->slot_id = 0;
    t->attach = aws_attach;
    t->detach = aws_detach;
    t->poke   = aws_poke;
    t->peek   = aws_peek;
    t->priv   = st;
    return t;
}

#else

npu_transport_t *npu_transport_create_aws(void) {
    fprintf(stderr, "AWS FPGA SDK not enabled in this build. Use mock transport or compile with -DAWS_FPGA.\n");
    return NULL;
}

#endif

void npu_transport_destroy(npu_transport_t*t) { if(t) { free(t->priv); free(t); } }
