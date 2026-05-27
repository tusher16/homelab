# ADR-0002: cert-manager DNS-01 over HTTP-01

**Status:** Accepted  
**Date:** May 2026

## Context

Public services sit behind Cloudflare. Certificates need to renew automatically without depending on direct HTTP access to the origin.

## Decision

Use cert-manager with the Cloudflare DNS-01 solver.

## Reasoning

- DNS-01 works while Cloudflare proxying is enabled.
- Certificate issuance does not require inbound HTTP challenge traffic.
- It keeps TLS automation inside Kubernetes manifests.

## Consequences

- Requires Cloudflare API tokens stored outside the public repo.
- Separate DNS solver configuration is needed for domains managed under different Cloudflare accounts.
