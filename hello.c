#include <stdint.h>
#include <microkit.h>

void
init(void)
{
    microkit_dbg_puts("hello, world\n");
}

void
notified(microkit_channel ch)
{
}
