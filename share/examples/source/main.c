#include "foo.h"
#include <stdio.h>

int
main ()
{
    printf ("Welcome to GNU Hell!\n");

    /* Try assigning to the nothing variable. */
    nothing = 1;

    /* Just call the functions and check return values. */
    if (foo () != FOO_RET)
      return 1;

    if (hello () != HELLO_RET)
      return 2;

    return 0;
}

