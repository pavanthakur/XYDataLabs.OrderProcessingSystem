# Phase 10 Architecture Exception Manifest

This manifest records the temporary architecture exceptions that remain allowed during the
pre-Azure Phase 10 cutover. New exceptions are not permitted without updating this manifest
and the matching architecture test.

All entries must contain:

- owner
- reason
- location
- replacement design
- removal milestone

## Active Exceptions

None. The temporary `Orders -> Products` cross-context read was removed by moving order creation onto an inventory-owned product snapshot seam.
