# instant-cf Architecture

## Overview

instant-cf provides a containerized Cloud Foundry deployment for local development and testing. It uses [bob (BOSH OCI Builder)](https://github.com/rkoster/bosh-oci-builder) to convert Cloud Foundry BOSH releases into OCI container images.

## Design Philosophy

1. **Iterative Colocation**: Start with multiple containers (proven pattern), consolidate to single container (ultimate goal)
2. **Minimal Memory**: Optimize for low resource usage (<8GB RAM target)
3. **Fast Startup**: Prioritize quick container startup (<10 min target)
4. **Static Networking**: Use Docker networks with static IPs for predictable container communication
5. **Standard CF**: Use upstream cf-deployment with minimal modifications

## Technology Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Build Tool** | bob (BOSH OCI Builder) | Converts BOSH manifests to containers |
| **Templating** | ytt | Programmatic manifest generation for colocation |
| **Database** | postgres-release | Simpler than PXC MySQL (1 job vs 7) |
| **Blobstore** | singleton-blobstore | Embedded for true all-in-one |
| **DNS** | nip.io | Easiest for local development |
| **Base CF** | cf-deployment v53.8.0 | Latest stable release |
| **Stemcell** | ubuntu-jammy | Standard CF stemcell |
| **Releases** | Compiled releases | Faster build times |

## Phase 1: Multi-Container Architecture (MVP)

### Network Topology

```
Docker Network: instant-cf (10.245.0.0/24)
├── Gateway: 10.245.0.1
│
├── instant-cf-database (10.245.0.10)
│   ├── Image: ghcr.io/rkoster/instant-cf-database:latest
│   └── Ports: 5524 (postgres)
│
├── instant-cf-control (10.245.0.20)
│   ├── Image: ghcr.io/rkoster/instant-cf-control:latest
│   └── Ports: 80/443 (apps), 8080 (API), 2222 (SSH)
│
└── instant-cf-runtime (10.245.0.30)
    ├── Image: ghcr.io/rkoster/instant-cf-runtime:latest
    └── Ports: None (internal only)
```

### Container Details

#### Database Container (10.245.0.10)

**Purpose**: Dedicated PostgreSQL database for all CF components

**Instance Group**: `database`

**Jobs** (1 total):
- `postgres` (from postgres-release)

**Databases Provided**:
- cloud_controller
- uaa
- diego
- routing-api
- network_policy
- network_connectivity
- locket
- credhub (if enabled)

**Resource Estimates**:
- Memory: 512MB-1GB
- Disk: 2GB + persistent volume
- Startup: 30-60 seconds

**Volumes**:
- `/var/vcap/store` - Persistent data (postgres data directory)
- `/var/vcap/data` - Runtime data

---

#### Control Plane Container (10.245.0.20)

**Purpose**: All CF control plane components colocated

**Instance Group**: `cf-control-plane` (colocated)

**Jobs** (~35-37 total):

From `nats`:
- `nats-tls` - Message bus

From `uaa`:
- `uaa` - Authentication and authorization
- `route_registrar` - Register UAA routes
- `statsd_injector` - Metrics

From `singleton-blobstore`:
- `blobstore` - Droplet and package storage
- `route_registrar` - Register blobstore routes

From `api` (22 jobs):
- `valkey` - Redis alternative for CC
- `cloud_controller_ng` - Main CF API
- `binary-buildpack`
- `dotnet-core-buildpack`
- `go-buildpack`
- `java-buildpack`
- `nodejs-buildpack`
- `nginx-buildpack`
- `r-buildpack`
- `php-buildpack`
- `python-buildpack`
- `ruby-buildpack`
- `staticfile-buildpack`
- `route_registrar` - API routes
- `statsd_injector` - Metrics
- `file_server` - Diego file server
- `routing-api` - Routing table API
- `policy-server` - Network policy

From `cc-worker`:
- `cloud_controller_worker` - Background jobs
- `loggr-udp-forwarder` - Logging

From `scheduler`:
- `cfdot` - Diego debugging tool
- `auctioneer` - Diego LRP placement
- `cloud_controller_clock` - CC periodic jobs
- `cc_deployment_updater` - Rolling deployments
- `service-discovery-controller` - Service discovery
- `statsd_injector` - Metrics
- `tps` - Task placement service
- `ssh_proxy` - App SSH proxy
- `loggr-syslog-binding-cache` - Syslog binding cache
- `loggr-udp-forwarder` - Logging

From `diego-api`:
- `cfdot` - Diego debugging tool
- `bbs` - Diego database
- `silk-controller` - Container networking
- `locket` - Distributed locks
- `loggr-udp-forwarder` - Logging

From `router`:
- `gorouter` - HTTP/HTTPS routing
- `loggr-udp-forwarder` - Logging

From `tcp-router` (optional):
- `tcp_router` - TCP routing
- `loggr-udp-forwarder` - Logging

From `doppler`:
- `doppler` - Log aggregation

From `log-api`:
- `loggregator_trafficcontroller` - Log streaming
- `reverse_log_proxy` - gRPC log proxy
- `reverse_log_proxy_gateway` - HTTP log gateway
- `route_registrar` - Log API routes

**Skipped Initially**:
- `credhub` instance group (all jobs) - Runtime credential management
- `log-cache` instance group (all jobs) - Advanced log querying

**Resource Estimates**:
- Memory: 2-4GB
- Disk: 5GB + persistent volumes
- Startup: 2-4 minutes

**External Dependencies**:
- Database: `10.245.0.10:5524`
- Blobstore: `localhost` (colocated)

**Volumes**:
- `/var/vcap/store` - Persistent state (vars-store.yml, certs, etc.)
- `/var/vcap/data` - Runtime data (blobstore, logs)

**Port Mappings**:
- `80:80` - HTTP apps
- `443:443` - HTTPS apps
- `8080:9022` - Cloud Controller API
- `2222:2222` - SSH proxy for app SSH

---

#### Runtime Container (10.245.0.30)

**Purpose**: Application runtime (Diego Cell)

**Instance Group**: `diego-cell`

**Jobs** (13 total):
- `bosh-dns-adapter` - DNS for containers
- `cflinuxfs4-rootfs-setup` - Container rootfs
- `garden` - Container runtime
- `rep` - Diego cell representative
- `cfdot` - Diego debugging tool
- `route_emitter` - Register app routes
- `garden-cni` - Container networking plugin
- `netmon` - Network monitoring
- `vxlan-policy-agent` - Network policy enforcement
- `silk-daemon` - Container networking
- `loggr-udp-forwarder` - Logging
- `loggr-syslog-binding-cache` - Syslog binding cache

**Resource Estimates**:
- Memory: 2-3GB (varies with app workload)
- Disk: 10GB + persistent volume for app containers
- Startup: 1-2 minutes

**External Dependencies**:
- BBS: `10.245.0.20:8889`
- NATS: `10.245.0.20:4222`
- File Server: `10.245.0.20:8080`

**Volumes**:
- `/var/vcap/store` - Persistent state
- `/var/vcap/data` - Application containers and cache

**Notes**:
- Requires `--privileged` for Garden container runtime
- `evacuation_timeout_in_seconds: 0` for fast shutdown
- `set_kernel_parameters: false` for faster startup

---

### DNS and Routing

**System Domain**: `10.245.0.20.nip.io`

**Key Endpoints**:
- API: `https://api.10.245.0.20.nip.io`
- UAA: `https://uaa.10.245.0.20.nip.io`
- Login: `https://login.10.245.0.20.nip.io`
- Apps: `https://*.apps.10.245.0.20.nip.io`

**Apps Domain**: `apps.10.245.0.20.nip.io`

**nip.io Benefits**:
- No /etc/hosts modification needed
- Works out of the box
- Supports wildcard DNS for apps

**Alternative** (offline environments):
- Use local dnsmasq or /etc/hosts entries
- System domain: `instant-cf.local`

---

### Resource Requirements (Phase 1)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU** | 2 cores | 4+ cores |
| **Memory** | 4GB | 6-8GB |
| **Disk** | 20GB | 50GB |
| **Startup Time** | N/A | 3-5 minutes |

**Breakdown by Container**:
- Database: 512MB RAM, 2GB disk
- Control: 2-4GB RAM, 5GB disk
- Runtime: 2-3GB RAM, 10GB disk

---

## Phase 2a: Two-Container Architecture

**Goal**: Consolidate to reduce complexity once Phase 1 is proven

### Container Structure

```
instant-cf Docker Network (10.245.0.0/24)
│
├── instant-cf-data (10.245.0.10)
│   ├── postgres (database)
│   └── blobstore
│
└── instant-cf-platform (10.245.0.20)
    ├── All control plane jobs (~35)
    └── All runtime jobs (13)
```

**Changes from Phase 1**:
- Merge database + blobstore → `instant-cf-data`
- Merge control + runtime → `instant-cf-platform`

**Benefits**:
- Fewer containers to manage
- Simpler networking (only 2 IPs)
- Still separates data from platform

**Resource Estimates**:
- Data container: 1GB RAM
- Platform container: 5-6GB RAM
- Total: 6-7GB RAM

---

## Phase 2b: Single-Container Architecture (Ultimate Goal)

**Goal**: The "mega-container" - all CF in one container

### Container Structure

```
instant-cf Container (10.245.0.10)
└── cf-all (all ~47 jobs colocated)
    ├── postgres
    ├── blobstore
    ├── All control plane jobs
    └── All runtime jobs
```

**Changes from Phase 2a**:
- Merge everything into single instance group
- All networking becomes localhost
- Single vars-store for all components

**Benefits**:
- Simplest deployment (one container)
- No cross-container networking
- True "all-in-one" CF

**Challenges**:
- Largest container (~47 jobs)
- Longest startup time
- Most memory usage
- Never been done before!

**Resource Estimates**:
- Memory: 6-8GB
- Disk: 20GB + volumes
- Startup: 5-10 minutes

---

## Manifest Generation Strategy

### YTT Template Architecture

```
manifests/templates/
├── schema.yml              # Data values schema
├── values.yml              # Default configuration
│
├── lib/                    # Reusable functions
│   ├── colocation.star     # Instance group merging
│   └── networking.star     # IP and connection helpers
│
├── base/                   # Base transformations
│   ├── load-cf-deployment.yml
│   ├── apply-use-postgres.yml
│   ├── apply-bosh-lite.yml
│   └── skip-optional.yml
│
└── phases/                 # Phase-specific generation
    ├── phase1/
    │   ├── database.yml
    │   ├── control.yml
    │   └── runtime.yml
    ├── phase2a/
    │   ├── data.yml
    │   └── platform.yml
    └── phase2b/
        └── all.yml
```

### Key Transformations

**Base Layer** (applies to all phases):
1. Load cf-deployment.yml via vendir
2. Apply `use-postgres.yml` ops file (replace MySQL with Postgres)
3. Apply `bosh-lite.yml` ops file (scale to 1 instance per group)
4. Remove optional components (credhub, log-cache initially)

**Phase-Specific Layer**:
1. Select which instance groups to keep
2. Merge instance groups based on phase
3. Set static IPs
4. Update cross-container connection strings
5. Apply optimizations (evacuation_timeout=0, disable kernel tuning)

### Example: Control Plane Colocation

```yaml
#@ load("lib/colocation.star", "merge_instance_groups")
#@ load("@ytt:overlay", "overlay")

#! Merge multiple instance groups into cf-control-plane
#@ control_groups = ["nats", "uaa", "singleton-blobstore", "api", 
#@                   "cc-worker", "scheduler", "diego-api", 
#@                   "router", "tcp-router", "doppler", "log-api"]

#@overlay/match by=overlay.all
---
instance_groups:
#@ merged = merge_instance_groups(control_groups, "cf-control-plane")
- name: cf-control-plane
  instances: 1
  azs: [z1]
  networks:
  - name: instant-cf
    static_ips: [10.245.0.20]
  jobs: #@ merged.jobs
```

---

## Build Process

### Bob Build Flow

```
cf-deployment.yml + ops files
         ↓
    YTT Templates
         ↓
  Generated Manifests (Phase 1/2a/2b)
         ↓
       bob build
         ↓
    OCI Container Images
         ↓
   Docker Registry (ghcr.io)
```

### Build Command Example

```bash
# Generate manifests
./scripts/generate-manifests.sh

# Build database container
bob build \
  --manifest manifests/generated/instant-cf-phase1-database.yml \
  --output ghcr.io/rkoster/instant-cf-database:latest

# Build control container
bob build \
  --manifest manifests/generated/instant-cf-phase1-control.yml \
  --output ghcr.io/rkoster/instant-cf-control:latest

# Build runtime container
bob build \
  --manifest manifests/generated/instant-cf-phase1-runtime.yml \
  --output ghcr.io/rkoster/instant-cf-runtime:latest
```

### Build Performance

**Estimated Build Times** (first build):
- Database: 10-15 minutes (1 package to compile)
- Control: 30-45 minutes (~35 packages)
- Runtime: 20-30 minutes (~13 packages)
- **Total: ~60-90 minutes**

**Subsequent Builds** (with cache):
- 5-10 minutes per container (template rendering only)

---

## Runtime Process

### Container Startup Sequence

```
1. Create Docker network (instant-cf)
         ↓
2. Create persistent volumes
         ↓
3. Start database container
         ↓
4. Wait for postgres ready (health check)
         ↓
5. Start control container
         ↓
6. Wait for CF API ready (curl /v3/info)
         ↓
7. Start runtime container
         ↓
8. Wait for diego-cell registration
         ↓
9. System ready!
```

### Health Checks

**Database**:
```bash
pg_isready -h 10.245.0.10 -p 5524
```

**Control Plane**:
```bash
curl -k https://api.10.245.0.20.nip.io/v3/info
```

**Runtime**:
```bash
# Check diego-cell registered with BBS
cfdot actual-lrps | grep -q diego-cell
```

---

## Security Considerations

### Secrets Management

- All secrets generated by BOSH vars-store
- Stored in `/var/vcap/store/vars-store.yml` in control container
- Persisted via Docker volume
- Self-signed certificates for TLS

### Network Isolation

- Containers communicate via private Docker network (10.245.0.0/24)
- Only control container exposes ports to host
- Database and runtime are isolated

### Container Privileges

- Requires `--privileged` for Garden container runtime
- Root access needed for kernel parameter tuning
- Standard BOSH security model applies

---

## Comparison to Other CF Deployments

| Deployment Type | VMs/Containers | Memory | Startup | Use Case |
|-----------------|----------------|--------|---------|----------|
| **Production CF** | 50-100+ VMs | 100GB+ | Hours | Production workloads |
| **BOSH-lite** | 1 VM + containers | 16GB+ | 30-60 min | Local dev with BOSH |
| **cf-for-k8s** | Multiple pods | 8-16GB | 10-20 min | Kubernetes environments |
| **instant-cf (Phase 1)** | 3 containers | 4-6GB | 3-5 min | Local dev/testing |
| **instant-cf (Phase 2b)** | 1 container | 6-8GB | 5-10 min | Ultra-lightweight dev |

**instant-cf Advantages**:
- Lowest resource usage
- Fastest startup
- No BOSH director required
- Standard Docker workflow
- Upstream cf-deployment compatibility

**instant-cf Limitations**:
- Single-VM only (no HA)
- Not for production use
- Requires Docker
- Privileged containers

---

## Future Enhancements

### Possible Improvements

1. **Multi-architecture**: ARM64 support for Apple Silicon
2. **Volume drivers**: External storage for persistent data
3. **Backup/restore**: Automated backup of vars-store and database
4. **Metrics**: Prometheus exporter for container metrics
5. **CredHub integration**: Runtime credential management
6. **TCP routing**: Optional TCP router for non-HTTP apps
7. **Log Cache**: Advanced log querying capabilities
8. **Custom domains**: Support for custom SSL certificates

### Phase 3 and Beyond

- **Minimal CF**: Ultra-minimal variant with only essential components
- **Fast-mode**: Pre-rendered templates for <1 min startup
- **Cloud profiles**: Optimized configs for AWS/GCP/Azure local emulation
- **CI/CD integration**: GitHub Actions workflow for automated builds

---

## References

- [cf-deployment](https://github.com/cloudfoundry/cf-deployment) - Upstream CF deployment manifests
- [bob (BOSH OCI Builder)](https://github.com/rkoster/bosh-oci-builder) - Container build tool
- [instant-bosh](https://github.com/rkoster/instant-bosh) - Containerized BOSH director
- [postgres-release](https://github.com/cloudfoundry/postgres-release) - PostgreSQL BOSH release
- [ytt](https://carvel.dev/ytt/) - YAML templating tool

---

**Last Updated**: 2024-12-15  
**Version**: Phase 1 Architecture (Initial)
