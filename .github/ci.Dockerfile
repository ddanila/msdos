FROM ubuntu:24.04

RUN apt-get update -q \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc \
      libc6-dev \
      make \
      nasm \
      python3 \
      qemu-system-x86 \
      mtools \
 && rm -rf /var/lib/apt/lists/*
