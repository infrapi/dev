---
title: InfraPI dev stack
description: Develop an InfraPI API locally, against Kayra, etcd and APISIX on podman or docker, with no external connection.
weight: 10
---

# InfraPI dev stack

A local InfraPI to develop an API against: Kayra authenticates and
authorizes every request and reconciles subscriptions, APISIX routes Kayra
and your API, etcd stores both. Everything runs on podman or docker,
configured by one file, `dev.yaml`, and nothing reaches outside the stack's
network once the images are pulled. You create the stack, and talk to it,
with [infrapi-cli](https://infrapi.github.io/cli/getting-started/#1-install).

| I want to... | Go to |
|---|---|
| Install what is needed, create a stack, start it, log in, make a first call | [Getting started](getting-started.md) |
| Build an API and call it as a tenant, end to end | [Create an API](create-an-api.md) |
| Know what runs, how it is configured, the commands, how to reset | [The dev stack](dev-stack.md) |

Examples of calls to Kayra and to your API are given twice: with
`infrapi-cli`, then with `curl`.
