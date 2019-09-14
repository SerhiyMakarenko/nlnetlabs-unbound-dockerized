# General
[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](https://github.com/SerhiyMakarenko/nlnetlabs-unbound-dockerized/blob/nlnetlabs-unbound-resolver/stable/LICENSE)

Unbound is a validating, recursive, caching DNS resolver. It is designed to be fast and lean and incorporates modern features based on open standards.

# Usage
To run container you need to execute command listed below:
```
docker run -d --name nlnetlabs-unbound-resolver --net=host \
    -v /path/to/unbound.conf:/usr/local/etc/unbound/unbound.conf \
    serhiymakarenko/nlnetlabs-unbound-resolver:latest
```