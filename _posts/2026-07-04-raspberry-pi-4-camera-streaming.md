---
title: Streaming MJPEG from a Raspberry Pi 4 camera via Yocto Linux
description: A practical walkthrough of streaming OV5647 camera video over HTTP from a Pi 4 running a custom Yocto build — covering the bcm2835-unicam driver bug, libcamera integration, gstreamer pipelines, and a lightweight HTTP relay server.
date: 2026-07-04 18:00:00 +0200
tags:
  - raspberry-pi
  - embedded
  - linux
  - camera
  - streaming
  - yocto
---

I needed to stream video from an OV5647 camera module (Pi v1 Camera) over HTTP to a browser, running on a
Raspberry Pi 4 Model B with a custom Yocto Scarthgap (5.0.19) `core-image-base` build. The goal was to
minimize dependencies — no Python, no Node.js, just what the Yocto build provides.

This post covers every issue I hit and how I fixed them.

## The hardware and build setup

- **Board**: Raspberry Pi 4 Model B (BCM2711, 2 GB)
- **Camera**: OV5647 via CSI ribbon cable, `/dev/video0` is the `bcm2835-unicam` device
- **Build**: Yocto Scarthgap (5.0.19), `MACHINE=raspberrypi4-64`, `core-image-base`
- **Kernel**: 6.6.63-v8
- **Additional layers**: `meta-raspberrypi`, `meta-openembedded/meta-multimedia`

If you are setting up the OV5647 on a Pi 4 for the first time, start with the previous post:
[Debugging an OV5647 device tree overlay on Raspberry Pi 4]({% post_url 2026-07-04-ov5647-raspberry-pi-4-device-tree-overlay %}).
It covers the six fragments needed in the device tree overlay, the I2C mux topology,
and how to verify the camera is detected by the kernel.

With that in place, the camera overlay was working — `dtoverlay=ov5647` in `config.txt` gave us `/dev/video0`
and `media-ctl` showed the OV5647 subdev at `10-0036`. The hard part was getting it to stream.

## Problem 1: bcm2835-unicam rejects STREAMON

The first attempt was the obvious gstreamer pipeline:

```bash
gst-launch-1.0 v4l2src device=/dev/video0 ! \
  video/x-raw,width=640,height=480 ! \
  jpegenc ! multipartmux ! tcpserversink host=0.0.0.0 port=8080
```

This failed immediately:

```
VIDIOC_STREAMON: Invalid argument
```

The kernel driver (`bcm2835-unicam`) refused to start the stream. I tried every fix I could find:

- Different resolutions (640x480, 1296x972, 1920x1080)
- Different pixel formats (YUYV, RGB3, JPEG via `pixelformat=JPEG`)
- Memory-mapped (`--stream-mmap`) vs user-pointer vs read-write buffers
- `v4l2-ctl --stream-mmap --stream-count=10` — same `EINVAL`
- Increasing CMA to 256 MB via `CMA=256M` in `config.txt` — confirmed free with `cat /proc/meminfo | grep CmaFree`
- `gpu_mem=128` in `config.txt`

None worked.

The reason is architectural. The Pi's camera pipeline is not a simple V4L2 video device. The `bcm2835-unicam`
driver is a media-controller device that requires the full pipeline to be configured before streaming:
unicam receiver → ISP → codec. The media graph looks like this:

```
ov5647 10-0036                  (sensor subdev)
  → bcm2835-unicam (video0)     (CSI-2 receiver)
    → bcm2835-isp (video13-16)  (image signal processor)
      → bcm2835-codec (video20-23, video31) (encoder/decoder)
```

Without linking these entities via `media-ctl`, the unicam driver refuses to start. The sensor driver
(`ov5647`) returns success on `VIDIOC_S_FMT` because the format is valid, but `VIDIOC_STREAMON` on
the unicam video node triggers `s_stream()` on the pipeline, which expects the full graph to be
configured via the media controller API. Since we configured only the video node directly, the
media-controller links are missing, and `s_stream()` returns `-EINVAL`.

### The fix: libcamera

[libcamera](https://libcamera.org/) is the official camera stack for Raspberry Pi. It handles the media
controller pipeline setup automatically — it opens the sensor subdev, configures formats on each
element in the pipeline, creates the media links, and then starts streaming. It exposes a simple
camera API that gstreamer can use through its `libcamerasrc` element.

To add libcamera to the Yocto build:

```bash
# In local.conf
IMAGE_INSTALL:append = " libcamera libcamera-gst"
PACKAGECONFIG:append:pn-libcamera = " gst"
CMDLINE_CMA = "cma=256M"

# In bblayers.conf — add meta-multimedia layer
BBLAYERS += "${BSPDIR}/sources/meta-openembedded/meta-multimedia"
```

The `PACKAGECONFIG` enables gstreamer integration (building the `libcamerasrc` element). The `cma=256M`
ensures enough contiguous memory for camera buffers.

After `bitbake core-image-base`, flashing, and booting, `cam --list` confirms detection:

```
Available cameras:
1: 'ov5647' (/base/soc/i2c0mux/i2c@1/ov5647@36)
Registered camera ... to Unicam device /dev/media2 and ISP device /dev/media1
```

The key line is the **registered to ISP device** — libcamera automatically linked the unicam and ISP
pipelines.

## Problem 2: gstreamer pipeline construction

With libcamera available, the gstreamer pipeline starts:

```bash
gst-launch-1.0 libcamerasrc ! \
  videoconvert ! jpegnc ! \
  multipartmux ! tcpserversink host=0.0.0.0 port=8081
```

This actually works, but produces a raw TCP stream of MJPEG data without HTTP headers. Browsers
need an `HTTP/1.0 200 OK` response with `Content-Type: multipart/x-mixed-replace; boundary=...`
before the MJPEG bytes.

`tcpserversink` is just a TCP socket sink — it does not speak HTTP. You need something in front
that wraps the stream with an HTTP response header.

### The HTTP relay

I wrote a small C program that listens on port 8080, accepts HTTP connections, reads (and discards)
the request, sends the HTTP response header, then connects to the gstreamer TCP port (8081) and
relays bytes:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/wait.h>

int main(int argc, char **argv) {
    signal(SIGCHLD, SIG_IGN);

    int http_port = 8080;
    int stream_port = 8081;
    if (argc > 1) http_port = atoi(argv[1]);
    if (argc > 2) stream_port = atoi(argv[2]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { perror("socket"); return 1; }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(http_port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind"); return 1;
    }
    listen(server_fd, 5);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t len = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &len);
        if (client_fd < 0) { perror("accept"); continue; }

        // Consume the HTTP request
        char buf[4096];
        ssize_t rv = read(client_fd, buf, sizeof(buf));
        (void)rv;

        // Connect to gstreamer tcpserversink
        int stream_fd = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in stream_addr = {0};
        stream_addr.sin_family = AF_INET;
        stream_addr.sin_port = htons(stream_port);
        stream_addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        if (connect(stream_fd, (struct sockaddr*)&stream_addr, sizeof(stream_addr)) < 0) {
            const char *err = "HTTP/1.0 502 Bad Gateway\r\n"
                              "Content-Type: text/plain\r\n\r\nStream unavailable\n";
            write(client_fd, err, strlen(err));
            close(client_fd);
            continue;
        }

        // Send HTTP response header
        const char *header =
            "HTTP/1.0 200 OK\r\n"
            "Content-Type: multipart/x-mixed-replace;"
            " boundary=023f8b3d8b1d4f8e\r\n"
            "\r\n";
        write(client_fd, header, strlen(header));

        // Fork — child relays bytes, parent accepts next connection
        pid_t pid = fork();
        if (pid < 0) {
            close(stream_fd);
            close(client_fd);
            continue;
        }
        if (pid == 0) {
            close(server_fd);
            char data[65536];
            ssize_t n;
            while ((n = read(stream_fd, data, sizeof(data))) > 0) {
                write(client_fd, data, n);
            }
            close(stream_fd);
            close(client_fd);
            _exit(0);
        }
        close(stream_fd);
        close(client_fd);
    }
    close(server_fd);
    return 0;
}
```

The relay forks for each client so multiple browsers can watch simultaneously. It is cross-compiled
using the Yocto SDK:

```bash
source /opt/poky/5.0.19/environment-setup-cortexa72-poky-linux
$CC -o mjpeg-server mjpeg-server.c
```

Then scp'd to the Pi and run alongside gstreamer:

```bash
# Start gstreamer pipeline (background)
gst-launch-1.0 libcamerasrc ! videoconvert ! jpegenc ! \
  multipartmux ! tcpserversink host=0.0.0.0 port=8081 &

# Start HTTP relay
./mjpeg-server 8080 8081
```

## Problem 3: pipeline stalls without queues

The initial pipeline had no `queue` elements. When no browser was connected, `tcpserversink` had
no client socket to send data to, and would stop consuming buffers from upstream. This stalled the
entire gstreamer pipeline — libcamerasrc, the encoder, everything. When a browser finally connected,
the pipeline had to re-prime from scratch, adding seconds of delay before the first frame arrived.

The fix is to insert `queue` elements between each stage. A `queue` buffers a configurable number
of buffers (default: 10), decoupling upstream from downstream. Even when `tcpserversink` pauses
(no client), the queue keeps the pipeline running:

```bash
gst-launch-1.0 libcamerasrc ! queue ! \
  videoconvert ! queue ! \
  capsfilter caps="video/x-raw,width=640,height=480" ! \
  videoscale ! queue ! \
  v4l2jpegnc ! queue ! \
  multipartmux boundary=023f8b3d8b1d4f8e ! queue ! \
  tcpserversink host=0.0.0.0 port=8081
```

## Problem 4: software JPEG encoding is slow

The initial pipeline used `jpegnc` (software JPEG encoder). On the Pi 4's Cortex-A72, at 1280x1080
resolution, this achieved about 19 fps. The Pi has a hardware JPEG encoder available at `/dev/video31`
(`bcm2835-codec-encode`) that gstreamer can use via the `v4l2jpegnc` element.

Switching to the hardware encoder raised the frame rate to 30+ fps at the same resolution:

```bash
gst-launch-1.0 libcamerasrc ! videoconvert ! v4l2jpegnc ! ...
```

Reducing resolution to 640x480 via `videoscale` + `capsfilter` further improves performance and
reduces network bandwidth:

```bash
gst-launch-1.0 libcamerasrc ! videoconvert ! \
  capsfilter caps="video/x-raw,width=640,height=480" ! \
  videoscale ! v4l2jpegnc ! ...
```

## Problem 5: mismatched multipart boundary

This was the most frustrating bug. The browser would connect, hang for over a minute, and eventually
time out. The HTTP response looked correct at a glance, and raw TCP dumps showed JPEG data arriving.

The cause was a subtle mismatch in the multipart boundary string. The `mjpeg-server.c` sent:

```
Content-Type: multipart/x-mixed-replace; boundary=--023f8b3d8b1d4f8e
```

Note the `--` prefix on the boundary value. In MIME multipart, the `boundary` parameter should be
the raw boundary string **without** the `--` prefix. The `--` is added by the protocol when
delimiting parts. The `multipartmux` element in gstreamer generates `--023f8b3d8b1d4f8e` as part
separators, so the header should say `boundary=023f8b3d8b1d4f8e`.

With `boundary=--023f8b3d8b1d4f8e` in the header but `--023f8b3d8b1d4f8e` in the body, the browser
expected `----023f8b3d8b1d4f8e` as the separator (adding its own `--` to the declared boundary)
and never found a match. It buffered data indefinitely waiting for the first complete part.

The fix was trivial — remove the `--` from the boundary in the HTTP header, and pass the same
string to `multipartmux boundary=...`:

```c
const char *header =
    "HTTP/1.0 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace; boundary=023f8b3d8b1d4f8e\r\n"
    "\r\n";
```

```bash
gst-launch-1.0 ... multipartmux boundary=023f8b3d8b1d4f8e ! ...
```

## The final setup

Two processes run on the Pi:

**Process 1** — gstreamer pipeline (starts first, runs continuously):

```bash
gst-launch-1.0 \
  libcamerasrc ! queue ! \
  videoconvert ! queue ! \
  capsfilter caps="video/x-raw,width=640,height=480" ! \
  videoscale ! queue ! \
  v4l2jpegnc ! queue ! \
  multipartmux boundary=023f8b3d8b1d4f8e ! queue ! \
  tcpserversink host=0.0.0.0 port=8081
```

**Process 2** — HTTP relay (started after pipeline is ready):

```bash
./mjpeg-server 8080 8081
```

Browse to `http://192.168.0.117:8080/` to view the stream.

## Performance comparison

| Metric | Before | After |
|--------|--------|-------|
| Resolution | 1280×1080 | 640×480 |
| JPEG encoder | software (`jpegnc`) | hardware (`v4l2jpegnc`) |
| Pipeline buffers | none | `queue` between every stage |
| Frame rate | ~19 fps | ~32 fps |
| First frame latency | >60 s (boundary mismatch) | ~11 ms |
| Frame size | ~185 KB | ~38 KB |

## Summary of issues

| Problem | Root cause | Fix |
|---------|-----------|-----|
| `VIDIOC_STREAMON: EINVAL` | bcm2835-unicam needs media-controller pipeline setup | Use `libcamerasrc` instead of `v4l2src` |
| Browser timeout / no frames | Multipart boundary mismatch in HTTP header | Match `boundary=` in header with `multipartmux boundary=` |
| Slow initial connection | No `queue` elements — pipeline stalls without a consumer | Add `queue` between every element |
| Low frame rate | Software JPEG encoding on CPU | Use `v4l2jpegnc` (hardware encoder) |
| High bandwidth | 1280×1080 frames ~185 KB each | Downscale to 640×480 via `videoscale` |

The core takeaway: the Pi's camera pipeline is non-trivial because of the media-controller
architecture. libcamera abstracts this correctly, but the gstreamer plumbing around it
(queues, HTTP wrapper, boundary strings) has its own set of subtle traps.
