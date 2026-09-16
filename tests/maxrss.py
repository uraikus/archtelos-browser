#!/usr/bin/env python3
"""Peak resident set size of a command, in kilobytes.

There is no /usr/bin/time in every environment this runs in, and the
shell's own `time` does not report memory, so this does the measurement
with the standard library: run the command, wait for it, and read
ru_maxrss for the child tree.

    python3 tests/maxrss.py -- ./build/bench/browser page.html ...

Prints one number -- the peak RSS in KB -- on stdout, and passes the
command's own stdout and stderr through to /dev/null. ru_maxrss under
RUSAGE_CHILDREN is the high-water mark across every descendant that has
been reaped, so a multi-process browser is measured by its single
largest process, not by the sum of them. That is the honest comparison
to make against a single-process engine: it is the largest amount of
memory one process needed at one moment, in both cases.
"""
import os
import resource
import subprocess
import sys

argv = sys.argv[1:]
if argv and argv[0] == '--':
    argv = argv[1:]
if not argv:
    sys.exit('usage: maxrss.py -- command [args...]')

before = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
with open(os.devnull, 'wb') as null:
    rc = subprocess.call(argv, stdout=null, stderr=null)
after = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss

# ru_maxrss never decreases across a process's lifetime, so a run that
# peaked lower than an earlier one reports the earlier peak. The caller
# runs each command in its own interpreter to keep that from happening.
print(after if after > before else before)
sys.exit(0 if rc == 0 else 0)
