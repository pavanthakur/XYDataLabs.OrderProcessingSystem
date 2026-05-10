# Side Project Repository Boundary

This repository may describe how to bootstrap future side projects, but it must not hold detailed domain-specific implementation documents for those products.

## Rule

- Keep bootstrap and template mechanics in [side-project-bootstrap-quick-start.md](../side-project-bootstrap-quick-start.md).
- Keep snapshot, branch, tag, and blueprint governance in [branch-and-blueprint-strategy.md](../../../internal/branch-and-blueprint-strategy.md).
- Keep only lightweight product-name references and bootstrap guidance in this repository.
- Create all domain-specific planning, architecture, ADRs, backlog, and implementation documents in the target side-project repository after bootstrap.

## Transfer Model

The intended flow is:

`XYDataLabs.OrderProcessingSystem` → `XYDataLabs.SideProjects` → `XYDataLabs.<ProductName>`

- `XYDataLabs.OrderProcessingSystem` is the upstream source for templates, bootstrap rules, architectural guardrails, and approved technology-adoption patterns.
- `XYDataLabs.SideProjects` is the planning registry that records priority, naming, and chosen bootstrap path.
- `XYDataLabs.<ProductName>` is the actual implementation repository and becomes the canonical home for product documentation and code.

## Current Candidate Products

- `AIJobApplication`
- `AIClinicAppointmentSystem`
- `IndiaTradingSystem`
- `AIRecruitment`

## Operating Note

The temporary planning home for the recovered candidate-product docs is [XYDataLabs.SideProjects](https://github.com/pavanthakur/XYDataLabs.SideProjects). When a real side-project repository is created, the first documentation commit in that repository should establish its own README, internal planning surface, ADR folder, implementation roadmap, and explicit bootstrap provenance. Do not continue expanding product-specific docs inside `XYDataLabs.OrderProcessingSystem`.