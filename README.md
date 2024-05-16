---
display_name: Projector
description: Projector in Docker
icon: ../../../site/static/icon/projector.png
maintainer_github: coder
verified: true
tags: [docker, container, projector, jetbrains]
---

# Remote Development on Projector

Provision Projector using Docker containers as [Coder
workspaces](https://coder.com/docs/v2/latest/workspaces) with this example
template.

This mimics how it was done in v1, where the IDE is already installed in the
image and Coder provides the Projector server and modifies the script for the
installed IDE to make it work in Projector.

In v1 we bundled the server with the agent and also had a small patch to force
the window to resize itself on first launch (included in the `build` directory).

That patch could be applied by compiling from source, however in this example we
just use the official server release.

## Possible alternatives

- Could possibly base off this image:
  https://github.com/JetBrains/projector-docker
- Instead of installing and patching manually, could use the Projector installer
  which does both for you: https://github.com/JetBrains/projector-installer

## Prerequisites

### Infrastructure

The VM you run Coder on must have a running Docker socket and the `coder` user must be added to the Docker group:

```sh
# Add coder user to Docker group
sudo adduser coder docker

# Restart Coder server
sudo systemctl restart coder

# Test Docker
sudo -u coder docker ps
```

## Architecture

This template provisions the following resources:

- Docker image (built by Docker socket and kept locally)
- Docker container pod (ephemeral)
- Docker volume (persistent on `/home/coder`)

This means, when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the container image. Alternatively, individual developers can [personalize](https://coder.com/docs/v2/latest/dotfiles) their workspaces with dotfiles.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.

### Editing the image

Edit the `Dockerfile` and run `coder templates push` to update workspaces.
