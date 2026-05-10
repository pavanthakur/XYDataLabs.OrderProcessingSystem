# Side Project Repository Boundary

This repository may describe how to bootstrap future side projects, but it must not hold detailed domain-specific implementation documents for those products.

## Rule

- Keep bootstrap and template mechanics in [side-project-bootstrap-quick-start.md](../side-project-bootstrap-quick-start.md).
- Keep snapshot, branch, tag, and blueprint governance in [branch-and-blueprint-strategy.md](../../../internal/branch-and-blueprint-strategy.md).
- Keep only lightweight product-name references and bootstrap guidance in this repository.
- Create all domain-specific planning, architecture, ADRs, backlog, and implementation documents in the target side-project repository after bootstrap.

## Current Candidate Products

- `trading-analytics`
- `whatsapp-automation`
- `azure-cost-optimizer`
- `ai-recruitment`
- `hospital-clinic-appointments`

## Operating Note

When a new side-project repository is created, the first documentation commit in that repository should establish its own README, internal planning surface, ADR folder, and implementation roadmap. Do not continue expanding product-specific docs inside `XYDataLabs.OrderProcessingSystem`.