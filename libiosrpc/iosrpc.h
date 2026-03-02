#ifndef IOSRPC_H
#define IOSRPC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t dclogin(const char *token);
int32_t dclogout(void);
int32_t startrpc(const char *icon, const char *title, const char *description, const char *button);
int32_t stoprpc(void);

// Optional helpers
const char *dclast_error(void);
const char *dcrpc_snapshot_json(void);

#ifdef __cplusplus
}
#endif

#endif
