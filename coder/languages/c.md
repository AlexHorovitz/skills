## License

© 2026 Alex Horovitz. Shareware License.

You are free to use this skill for personal and internal organizational purposes 
at no cost. Redistribution, resale, or incorporation into commercial products or 
services requires written permission from the author.

If this skill saves you time, improves your work, or sparks something useful, 
a small contribution is appreciated: venmo.com/alex-horovitz

No warranty is expressed or implied. Use at your own discretion.


# C — Language Reference

Loaded by `coder/SKILL.md` when the project is C (C99, C11, C17, or C23).

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Functions | lowercase_snake_case | `subscription_create()`, `user_get_by_id()` |
| Types (struct, enum, typedef) | lowercase_snake_case or UpperCamelCase (pick one, stay consistent) | `subscription_t`, `SubscriptionStatus` |
| Constants / macros | SCREAMING_SNAKE_CASE | `MAX_RETRY_COUNT`, `BUFFER_SIZE` |
| Global variables | `g_` prefix + snake_case | `g_connection_pool` |
| File-scope statics | `s_` prefix + snake_case | `s_instance_count` |
| Struct fields | lowercase_snake_case | `expires_at`, `is_active` |

Prefix all public symbols with a module prefix to avoid name collisions in C's flat namespace:

```c
// module: subscription
subscription_t*  subscription_create(uuid_t user_id, uuid_t plan_id);
void             subscription_destroy(subscription_t* sub);
int              subscription_cancel(subscription_t* sub, const char* reason);
```

---

## Header Organization

Every module has a `.h` + `.c` pair. Headers declare; sources define.

```c
/* subscription.h */
#ifndef SUBSCRIPTION_H
#define SUBSCRIPTION_H

#include <stdint.h>
#include <stdbool.h>
#include "uuid.h"

/* --- Types --- */
typedef enum {
    SUBSCRIPTION_STATUS_ACTIVE    = 0,
    SUBSCRIPTION_STATUS_PAUSED    = 1,
    SUBSCRIPTION_STATUS_CANCELLED = 2,
    SUBSCRIPTION_STATUS_EXPIRED   = 3
} subscription_status_t;

typedef struct subscription_s subscription_t;  /* opaque handle */

/* --- Lifecycle --- */
subscription_t* subscription_create(uuid_t user_id, uuid_t plan_id);
void            subscription_destroy(subscription_t* sub);  /* always call this */

/* --- Operations --- */
int  subscription_cancel(subscription_t* sub, const char* reason);
bool subscription_is_valid(const subscription_t* sub);

#endif /* SUBSCRIPTION_H */
```

```c
/* subscription.c */
#include "subscription.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "logging.h"
#include "errors.h"

struct subscription_s {
    uuid_t user_id;
    uuid_t plan_id;
    subscription_status_t status;
    time_t expires_at;
};
```

---

## Memory Management

Every allocation has one owner. Document ownership in function signatures.

```c
/*
 * subscription_create — allocates and returns a new subscription.
 * Caller owns the returned pointer and must call subscription_destroy().
 * Returns NULL on allocation failure.
 */
subscription_t* subscription_create(uuid_t user_id, uuid_t plan_id) {
    subscription_t* sub = calloc(1, sizeof(subscription_t));
    if (!sub) {
        log_error("subscription_create: calloc failed");
        return NULL;
    }
    sub->user_id = user_id;
    sub->plan_id = plan_id;
    sub->status  = SUBSCRIPTION_STATUS_ACTIVE;
    return sub;
}

void subscription_destroy(subscription_t* sub) {
    if (!sub) return;   /* safe to call on NULL */
    free(sub);
}
```

Rules:
- `calloc` over `malloc` for zero-initialization
- Always check `malloc`/`calloc` return value — never assume success
- `free(NULL)` is safe; always null-check before dereferencing
- Use `valgrind` or address sanitizer to catch leaks during development

---

## Error Handling

C has no exceptions. Use return codes with `errno` for system errors, or a project-specific error enum:

```c
typedef enum {
    SUB_OK               = 0,
    SUB_ERR_NOT_FOUND    = -1,
    SUB_ERR_ALREADY_ACTIVE = -2,
    SUB_ERR_PAYMENT_FAILED = -3,
    SUB_ERR_INTERNAL     = -99
} sub_error_t;

sub_error_t subscription_cancel(subscription_t* sub, const char* reason) {
    if (!sub) return SUB_ERR_NOT_FOUND;
    if (sub->status != SUBSCRIPTION_STATUS_ACTIVE) return SUB_ERR_ALREADY_ACTIVE;

    sub->status = SUBSCRIPTION_STATUS_CANCELLED;
    log_info("subscription cancelled: reason=%s", reason ? reason : "(none)");
    return SUB_OK;
}
```

For output parameters, use out-pointer pattern:

```c
sub_error_t user_get_by_email(
    const char* email,
    user_t**    out_user   /* caller owns if SUB_OK */
);
```

---

## Buffer Safety

Never use `strcpy`, `strcat`, `sprintf`, `gets`. Always use the `n` variants:

```c
/* ❌ Dangerous */
strcpy(dst, src);
sprintf(buf, "user: %s", name);

/* ✅ Safe */
strncpy(dst, src, dst_size - 1);
dst[dst_size - 1] = '\0';   /* guarantee null-termination */
snprintf(buf, sizeof(buf), "user: %s", name);
```

Prefer keeping size alongside buffer:

```c
typedef struct {
    char*  data;
    size_t len;
    size_t capacity;
} string_buf_t;
```

---

## Struct Initialization

Use designated initializers (C99+) to avoid order-dependency bugs:

```c
/* ❌ Order-dependent, fragile */
subscription_t sub = { user_id, plan_id, SUBSCRIPTION_STATUS_ACTIVE, expiry };

/* ✅ Designated initializers */
subscription_t sub = {
    .user_id    = user_id,
    .plan_id    = plan_id,
    .status     = SUBSCRIPTION_STATUS_ACTIVE,
    .expires_at = expiry
};
```

---

## Build System (CMake)

```cmake
cmake_minimum_required(VERSION 3.20)
project(myservice C)
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_compile_options(-Wall -Wextra -Wpedantic -Werror)

add_library(subscription
    src/subscription.c
    src/user.c
)
target_include_directories(subscription PUBLIC include)

add_executable(myservice src/main.c)
target_link_libraries(myservice subscription)
```

Always compile with `-Wall -Wextra -Werror`. Warnings are errors.

---

## Testing (Unity or cmocka)

```c
/* test_subscription.c — using Unity */
#include "unity.h"
#include "subscription.h"

void test_subscription_cancel_sets_status(void) {
    subscription_t* sub = subscription_create(uuid_new(), uuid_new());
    TEST_ASSERT_NOT_NULL(sub);

    sub_error_t err = subscription_cancel(sub, "user request");

    TEST_ASSERT_EQUAL_INT(SUB_OK, err);
    TEST_ASSERT_EQUAL_INT(SUBSCRIPTION_STATUS_CANCELLED, subscription_get_status(sub));

    subscription_destroy(sub);
}

void test_subscription_cancel_null_returns_not_found(void) {
    sub_error_t err = subscription_cancel(NULL, NULL);
    TEST_ASSERT_EQUAL_INT(SUB_ERR_NOT_FOUND, err);
}
```

---

## C-Specific Quality Checklist

- [ ] All `malloc`/`calloc` return values checked for NULL
- [ ] Every allocation has a documented owner and matching `free`
- [ ] No `strcpy`, `strcat`, `sprintf`, `gets` — use `n` variants
- [ ] All public headers have include guards
- [ ] All public functions documented with ownership semantics
- [ ] `-Wall -Wextra -Werror` passes clean
- [ ] No VLAs (variable-length arrays) in security-sensitive or embedded contexts
- [ ] Designated struct initializers used (no position-dependent init)

---

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Segfault on dereference | NULL pointer not checked | Check return values; add NULL guard |
| Memory leak | `malloc` without `free` | Use valgrind; review ownership doc |
| Buffer overflow | `strcpy`/`sprintf` | Use `strncpy`/`snprintf` with explicit size |
| Use after free | Freeing then accessing | Set pointer to NULL after free |
| Stack corruption | Returning pointer to local var | Return heap-allocated or use out-param |
| Undefined behavior | Signed integer overflow | Use unsigned for bit ops; check overflow explicitly |
| Race condition | Unprotected shared state | Use `pthread_mutex_t` or atomic ops |
