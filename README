# Unbound Resolver Docker Image

A Docker image for [Unbound](https://nlnetlabs.nl/projects/unbound/about/) that's built from source with DoQ enabled as per the documentation.

## Features

This image builds Unbound from scratch along with:

- **OpenSSL 3.6.0** - Fresh crypto, built from source
- **ngtcp2** - Built from HEAD for DNS over QUIC (DoQ) support
- **Unbound** - The latest release with DoQ, DNSCrypt

## Quick Start

```bash
docker run -d \
  -p 53:53/udp \
  -p 53:53/tcp \
  -p 853:853/tcp \
  -p 853:853/udp \
  -v $(pwd)/config:/etc/unbound \
  -v unbound_data:/var/lib/unbound \
  adamliang0/unbound
```

### Volumes

The Docker image uses two main volume mounts:

- `-v $(pwd)/config:/etc/unbound`  
  Mounts your local `config` directory as Unbound's configuration directory in the container (`/etc/unbound`). Place your `unbound.conf` and any related configuration files in `./config` on your host. This allows for easy customization and persistence of Unbound settings.

- `-v unbound_data:/var/lib/unbound`  
  Mounts (and creates if needed) a Docker named volume `unbound_data` to persist data files used by Unbound at `/var/lib/unbound`. This stores runtime state such as root trust anchor files and DNSSEC validation data, so it persists across container restarts.
