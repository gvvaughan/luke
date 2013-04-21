#!/bin/sh
# Luke self-extractor script.
#
# Copyright (C) 2010, 2011 Gary V. Vaughan
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
for i in arch machine "uname -m"
do
A=`$i 2>/dev/null`
if test $? -eq 0&&test -n "$A"
then
break
fi
done
E='echo luke:'
if test $? -ne 0||test -z "$A"
then
A=unknown
$E unable to determine target type, proceeding with $A>&2
fi
X=.luke-$A
C=${TMPDIR-"/tmp"}/luke-$$.c
trap "rm -f $C" 0 1 2 13 15
if test "$X" -nt "$0"
then
"./$X" ${1+"$@"}
exit $?
fi
cat>$C<<'__%luke.c-EOH%__'
#include "luke.c"
__%luke.c-EOH%__
: ${CC='gcc'}
for i in $CC gcc cc icc tcc
do
$i -o $X $C 2>/dev/null
test $? -eq 0&&test -x $X&&exec "$0" ${1+"$@"}
$E checking for $i... no
done
$E bootstrap failed.
exit 1
