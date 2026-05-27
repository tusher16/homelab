# ADR-0001: K3s over full Kubernetes

**Status:** Accepted  
**Date:** May 2026

## Context

The homelab runs on refurbished hardware and needs Kubernetes-style production patterns without unnecessary control-plane overhead.

## Decision

Use K3s for the homelab cluster.

## Reasoning

- Single-command install.
- Built-in containerd.
- Built-in Traefik.
- Lightweight enough for refurbished x86 hardware.
- Good fit for future ARM monitoring/support nodes.

## Consequences

- Single control-plane node is a known homelab tradeoff.
- K3s-managed components, especially Traefik, must be customized through K3s-supported mechanisms such as `HelmChartConfig`.
