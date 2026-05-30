# Runtime image for the Garmin Connect IQ simulator GUI.
#
# Why this exists: the `simulator` binary is a native GTK/WebKit program that
# links against the libwebkit2gtk-4.0 / libjavascriptcoregtk-4.0 / libsoup-2.4
# series. Rolling distros (e.g. openSUSE Tumbleweed) have dropped the 4.0
# series in favour of 4.1, which breaks the simulator with:
#
#   error while loading shared libraries: libjavascriptcoregtk-4.0.so.18
#
# Ubuntu 22.04 LTS still ships the whole 4.0 series, so we run the simulator
# here and forward X11 to the host. The SDK and device data live on bind
# mounts supplied at run time (see `make sim-start`), so this image is just a
# stable bag of runtime libraries and is independent of the SDK version.
#
# The build toolchain (monkeyc/monkeydo) stays on the host: those are pure
# Java plus a generic native transport that still load fine. The host-side
# monkeydo reaches this container's simulator over loopback (127.0.0.1:1234),
# which is why `make sim-start` runs the container with --network host.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Direct DT_NEEDED libraries of `simulator` (readelf -d), plus the GL/font
# bits a GTK app needs at runtime. apt pulls the large transitive GTK/Pango/
# Cairo/GStreamer closure consistently within the distro.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libwebkit2gtk-4.0-37 \
      libjavascriptcoregtk-4.0-18 \
      libsoup2.4-1 \
      libgtk-3-0 \
      libsecret-1-0 \
      libusb-1.0-0 \
      libsm6 \
      libxxf86vm1 \
      libjpeg-turbo8 \
      libxkbcommon0 \
      libgl1 \
      libgl1-mesa-dri \
      libegl1 \
      libgles2 \
      libglu1-mesa \
      libgstreamer1.0-0 \
      libgstreamer-plugins-base1.0-0 \
      gstreamer1.0-plugins-good \
      fonts-dejavu-core \
      fonts-liberation \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# No GPU is passed into the container, so force the software GL stack
# (llvmpipe) and disable WebKit's GPU-assuming accelerated compositing.
ENV LIBGL_ALWAYS_SOFTWARE=1 \
    WEBKIT_DISABLE_COMPOSITING_MODE=1

# The actual command (path to .sdk/bin/simulator) is supplied by `make
# sim-start`; the SDK is bind-mounted, so nothing simulator-specific is baked
# into the image.
