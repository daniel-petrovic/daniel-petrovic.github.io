---
title: Running a Docker container with GUI on Fedora
description: A practical Fedora setup for running X11 GUI apps from a Docker container, including a working ROS Humble example and quick validation steps.
date: 2026-05-20 16:10:00 +0200
tags:
  - docker
  - fedora
  - linux
  - gui
  - ros
---

Running GUI apps from Docker on Fedora can be annoying because you usually need more than just `-e DISPLAY=$DISPLAY`.

For me, the following command worked with a `ros:humble` container:

```sh
docker run -it --rm \
  --privileged \
  --net=host \
  --ipc=host \
  -e DISPLAY=$DISPLAY \
  -e QT_QPA_PLATFORM=xcb \
  -e XAUTHORITY=/root/.Xauthority \
  -v $HOME/.Xauthority:/root/.Xauthority:ro \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  ros:humble
```

## What this setup is doing

- `-it` keeps the container interactive and attaches a TTY, which is useful when you want a shell and want to run test commands manually.
- `--rm` removes the container after exit so you do not keep around disposable test containers.
- `--privileged` gives the container broad access to host devices and kernel capabilities. It is much less restrictive than a normal container and can help when GUI, device, or shared-memory related permissions get in the way.
- `--net=host` puts the container on the host network stack instead of an isolated Docker network. For desktop and ROS tooling, this can remove a whole class of networking issues.
- `--ipc=host` shares the host IPC namespace with the container. Some GUI apps and ROS-related tools behave better with this because they can use the host shared-memory setup directly.
- `-e DISPLAY=$DISPLAY` tells GUI apps which X server display to connect to.
- `-e QT_QPA_PLATFORM=xcb` forces Qt apps to use the X11 backend through XCB. If you skip this, some Qt applications may pick an unsuitable platform plugin and fail to start correctly.
- `-e XAUTHORITY=/root/.Xauthority` tells X11 clients inside the container where to find the authority file with the authentication cookie.
- `-v $HOME/.Xauthority:/root/.Xauthority:ro` mounts your host X11 authority file into the container so the root user inside the container can present the same cookie to the X server.
- `-v /tmp/.X11-unix:/tmp/.X11-unix:rw` shares the X11 Unix domain socket directory with the container so GUI apps can actually connect to the host X server.

This is not the most locked-down setup, but it is a practical one when the goal is simply to get a Linux GUI app running inside the container on Fedora.

## What `.Xauthority` is

The `.Xauthority` file stores X11 authentication cookies.

When a GUI app wants to connect to your display, the X server does not just trust any local process automatically. It expects the client to present a matching cookie. That is why simply mounting `/tmp/.X11-unix` is often not enough on its own: the socket gives the container a path to the server, but `.Xauthority` gives it the credentials.

In this setup:

- the host file is `$HOME/.Xauthority`,
- it gets mounted into the container at `/root/.Xauthority`,
- and `XAUTHORITY=/root/.Xauthority` tells programs inside the container where to look.

That combination matters because the container is running as `root`, not as your host user.

## One extra step I needed on Fedora

I also had to run this on the host:

```sh
xhost +SI:localuser:root
```

This command tells the X server:

> allow the local user `root` to connect

The important part is `SI:localuser:root`:

- `SI` means *server interpreted* address,
- `localuser:root` means the local Unix user named `root`.

This helped because the process inside the container was running as `root`, and from the X server's point of view that local user access still mattered.

Even with `.Xauthority` mounted, X11 access control can still be the piece that blocks the connection. `xhost +SI:localuser:root` relaxes that policy specifically for the local `root` user, which is narrower and safer than something broad like `xhost +`.

If you want to remove that permission later, use:

```sh
xhost -SI:localuser:root
```

## Test a simple GUI first

Before debugging your real app, test X11 itself.

If needed, run the `xhost` command on the host first:

```sh
xhost +SI:localuser:root
```

Inside the container:

```sh
apt update
apt install -y x11-apps
xclock
```

If `xclock` opens, the basic X11 path is working.

You can also try:

```sh
xeyes
```

That is a good sanity check before moving on to bigger GUI applications such as ROS tools.

If `xclock` or `xeyes` fails with an error like "Can't open display" or an authorization error, the problem is usually one of these:

- `DISPLAY` is wrong,
- `.Xauthority` is missing or mounted to the wrong path,
- or the X server is still denying access and needs the `xhost +SI:localuser:root` step.

## Why this is useful

When you are trying to run tools like `rviz2`, simulator frontends, or other desktop applications from a container, it helps to separate the problem into two parts:

1. Can the container talk to the host display server?
2. Does the actual application start once basic X11 access works?

That is why starting with `xclock` or `xeyes` is worth it. If those do not open, the issue is usually the display bridge, not the application itself.

## Security note

This setup is useful for local development and testing, but it is intentionally permissive:

- `--privileged` greatly expands what the container can do,
- `--net=host` removes network isolation,
- and `xhost +SI:localuser:root` explicitly grants X server access to local root.

That can be fine for a trusted local container you are debugging, but it should not be your default pattern for arbitrary images.

## Final thought

If you are on Fedora and need a quick working baseline for Docker GUI apps, this command is a good starting point. It is especially useful when a plain `docker run -e DISPLAY=$DISPLAY ...` setup is not enough and you just want a containerized GUI to appear on screen first.
