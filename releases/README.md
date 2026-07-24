# Version archive

Each directory contains a frozen candidate or release binary, its SHA-256 checksum,
and a test-status note. Files in an existing version directory must only be refreshed
from a rebuild of that same `VERSION` before it is published.

`build/` is replaceable development output. `releases/` is versioned evidence.
