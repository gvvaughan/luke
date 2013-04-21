#include <stdio.h>
#include <math.h>

#include "foo.h"

int nothing = FOO_RET;

int
foo ()
{
    printf ("cos (0.0) = %g\n", (double) cos ((double) 0.0));
    return FOO_RET;
}
