---
title: InfraPI dev stack
description: Develop an InfraPI API locally, against Kayra, etcd and APISIX on podman, with no external connection.
weight: 10
---

# InfraPI dev stack

A local InfraPI to develop an API against: Kayra authenticates and
authorizes every request and reconciles subscriptions, APISIX routes Kayra
and your API, etcd stores both. Everything runs on podman, and nothing
reaches outside the stack's network once the images are built.

| I want to... | Go to |
|---|---|
| Build an API and call it as a tenant, end to end | [Create an API](create-an-api.md) |
| Know what runs, how it is configured, and the make targets | [The dev stack](dev-stack.md) |

Examples of calls to Kayra and to your API are given twice: with
`kayra-cli`, then with `curl`.
