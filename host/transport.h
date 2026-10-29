#ifndef NPU_TRANSPORT_H
#define NPU_TRANSPORT_H

#include <stdint.h>
#include <stddef.h>

typedef struct npu_transport npu_transport_t;

struct npu_transport {
    int (*attach)(npu_transport_t *t, int slot_id);
    void (*detach)(npu_transport_t *t);
    int (*poke)(npu_transport_t *t, uint32_t addr, uint32_t data);
    int (*peek)(npu_transport_t *t, uint32_t addr, uint32_t *data);
    void *priv;
};

// Factory functions
#ifdef __cplusplus
extern "C" {
#endif

npu_transport_t *npu_transport_create_aws(void);
void npu_transport_destroy(npu_transport_t *t);

#ifdef __cplusplus
}
#endif

#endif // NPU_TRANSPORT_H
