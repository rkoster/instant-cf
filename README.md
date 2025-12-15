# instant-cf

**Containerized Cloud Foundry for Local Development**

instant-cf provides a fully functional Cloud Foundry deployment running in Docker containers for local development and testing. Built with [bob (BOSH OCI Builder)](https://github.com/rkoster/bosh-oci-builder), it converts standard Cloud Foundry BOSH releases into optimized container images.

## Features

- **Fast Setup**: Start a complete CF environment in minutes
- **Low Resource Usage**: Runs in <6GB RAM (Phase 1 target)
- **Standard CF**: Based on upstream cf-deployment v53.8.0
- **Docker Native**: Uses standard Docker networking and volumes
- **Iterative Design**: Multi-container MVP, single-container future

## Quick Start

> **Note**: instant-cf is under active development. This quick start guide will be available when v0.1.0 is released.

```bash
# Install instant-cf (future)
go install github.com/rkoster/instant-cf/cmd/instant-cf@latest

# Start Cloud Foundry (future)
instant-cf start

# Login to CF
cf login -a https://api.10.245.0.20.nip.io --skip-ssl-validation \
  -u admin -p $(instant-cf password)

# Push your first app
cf push myapp
```

## Prerequisites

For **users** (when v0.1.0 is released):
- Docker Desktop or Docker Engine
- CF CLI

For **contributors** (current development):
- [devbox](https://www.jetpack.io/devbox/) - Development environment manager
- Docker Desktop or Docker Engine
- Go 1.21+

## Architecture

instant-cf uses an iterative colocation strategy:

**Phase 1 (MVP)**: 3 containers
- `instant-cf-database` - PostgreSQL database
- `instant-cf-control` - Control plane (~35 colocated jobs)
- `instant-cf-runtime` - Diego cell for running apps

**Phase 2a** (future): 2 containers (data + platform)

**Phase 2b** (future): 1 mega-container (ultimate goal)

For complete architectural details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Development

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/rkoster/instant-cf.git
cd instant-cf

# Install development dependencies with devbox
devbox shell

# Sync vendored dependencies (when available)
make sync

# Generate manifests (when available)
make generate
```

### Project Structure

```
instant-cf/
├── manifests/
│   ├── templates/          # YTT templates (future)
│   ├── generated/          # Generated BOSH manifests (gitignored)
│   └── cf-deployment/      # Vendored upstream (future)
├── cmd/instant-cf/         # CLI tool (future)
├── pkg/                    # Go libraries (future)
├── ARCHITECTURE.md         # Technical design
├── ROADMAP.md             # Implementation milestones
└── LICENSE                # BSL 1.1 license
```

### Implementation Progress

See [ROADMAP.md](ROADMAP.md) for the complete implementation plan.

**Current Status**: Milestone 0 - Bootstrap (in progress)

## Roadmap

instant-cf is being developed in 16 milestones:

- **Milestone 0-6**: Bootstrap, YTT templates, container builds
- **Milestone 7-11**: CLI tool development
- **Milestone 12-14**: Testing, documentation, Phase 1 release
- **Milestone 15-16**: Phase 2a/2b multi-container consolidation

See [ROADMAP.md](ROADMAP.md) for detailed milestone breakdown.

## Contributing

Contributions are welcome! This project is under active initial development.

### Contribution Guidelines

1. Read [ARCHITECTURE.md](ARCHITECTURE.md) and [ROADMAP.md](ROADMAP.md)
2. Check current milestone progress
3. Open an issue to discuss major changes
4. Submit PRs with clear descriptions

### Development Philosophy

- **Iterative approach**: Start simple, consolidate gradually
- **Minimize resources**: Every MB of RAM counts
- **Use bob**: If bob doesn't work, we fix bob
- **Standard CF**: Minimal modifications to upstream cf-deployment

## License

This project is licensed under the Business Source License 1.1. See [LICENSE](LICENSE) for details.

**Summary**:
- Free to use for development, testing, and evaluation
- Production use requires a commercial license after 4 years from release
- Source code is available and modifications are allowed
- Converts to Apache 2.0 four years after each version's release date

## Related Projects

- [instant-bosh](https://github.com/rkoster/instant-bosh) - Containerized BOSH Director
- [bob (BOSH OCI Builder)](https://github.com/rkoster/bosh-oci-builder) - Converts BOSH to containers
- [cf-deployment](https://github.com/cloudfoundry/cf-deployment) - Upstream Cloud Foundry manifests

## Support

- **Issues**: [GitHub Issues](https://github.com/rkoster/instant-cf/issues)
- **Discussions**: [GitHub Discussions](https://github.com/rkoster/instant-cf/discussions)

## Acknowledgments

Built with [bob](https://github.com/rkoster/bosh-oci-builder) by Ruben Koster.
Based on [cf-deployment](https://github.com/cloudfoundry/cf-deployment) by the Cloud Foundry Foundation.