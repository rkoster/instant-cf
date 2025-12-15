# instant-cf Implementation Roadmap

This roadmap breaks down the implementation into manageable, bite-sized chunks that can be completed incrementally.

---

## Milestone 0: Project Bootstrap
**Goal**: Set up repository structure and development environment  
**Time Estimate**: 2-4 hours

### 0.1 Repository Initialization
- [ ] Create `LICENSE` (BSL 1.1, copy from instant-bosh)
  - Update Licensor: Ruben Koster
  - Update Licensed Work: instant-cf
  - Update change date: 2029-12-15
- [ ] Create basic `README.md` with project overview
- [ ] Initialize `go.mod`: `go mod init github.com/rkoster/instant-cf`
- [ ] Create `.gitignore` (manifests/generated/, binaries, etc.)

### 0.2 Development Environment
- [ ] Create `devbox.json` with packages:
  - vendir@latest
  - go@latest
  - ytt@latest
  - bosh-cli@latest
  - cf-cli@latest
- [ ] Run `devbox init` and test environment

### 0.3 Dependency Vendoring
- [ ] Create `vendir.yml` to vendor cf-deployment v53.8.0
- [ ] Run `vendir sync`
- [ ] Verify `manifests/cf-deployment/` directory created

### 0.4 Build Automation
- [ ] Create `Makefile` with initial targets:
  - `help` - Show available commands
  - `sync` - Run vendir sync
  - `generate` - Generate manifests (placeholder)
- [ ] Create `.gitignore` entry for `manifests/generated/`

**Deliverable**: Repository with devbox, vendored cf-deployment, and Makefile

---

## Milestone 1: YTT Template Foundation
**Goal**: Create reusable YTT template library and data schema  
**Time Estimate**: 4-6 hours

### 1.1 Schema and Configuration
- [ ] Create `manifests/templates/schema.yml` with data values schema:
  - phase (1, 2a, 2b)
  - network configuration (name, subnet, static IPs)
  - system_domain and apps_domain
  - skip flags (credhub, tcp_router, log_cache)
- [ ] Create `manifests/templates/values.yml` with defaults:
  - phase: "1"
  - network.name: instant-cf
  - network.subnet: 10.245.0.0/24
  - system_domain: 10.245.0.20.nip.io

### 1.2 Starlark Library Functions
- [ ] Create `manifests/templates/lib/colocation.star`:
  - `merge_instance_groups(groups, new_name)` - Merge jobs from multiple instance groups
  - `extract_jobs(instance_group)` - Get all jobs from an instance group
  - `set_instances(instance_group, count)` - Set instance count
- [ ] Create `manifests/templates/lib/networking.star`:
  - `set_static_ip(instance_group, ip)` - Set static IP
  - `update_db_connection(jobs, db_host, db_port)` - Update DB connection strings
  - `update_blobstore_endpoint(jobs, endpoint)` - Update blobstore endpoints

### 1.3 Base Transformations
- [ ] Create `manifests/templates/base/load-cf-deployment.yml`:
  - Load cf-deployment.yml from vendored directory
- [ ] Create `manifests/templates/base/apply-use-postgres.yml`:
  - Apply use-postgres.yml ops file
  - Remove PXC MySQL jobs
  - Add postgres release and job
- [ ] Create `manifests/templates/base/apply-bosh-lite.yml`:
  - Scale all instance groups to 1 instance
  - Apply bosh-lite optimizations
- [ ] Create `manifests/templates/base/skip-optional.yml`:
  - Remove credhub instance group (if data.values.skip.credhub)
  - Remove log-cache instance group (if data.values.skip.log_cache)
  - Conditionally remove tcp-router

**Deliverable**: Reusable YTT library with schema and base transformations

---

## Milestone 2: Phase 1 Database Template
**Goal**: Generate database container manifest (simplest case)  
**Time Estimate**: 2-3 hours

### 2.1 Database Template
- [ ] Create `manifests/templates/phases/phase1/database.yml`:
  - Remove all instance groups except `database`
  - Set instances: 1
  - Set network: instant-cf
  - Set static IP: 10.245.0.10
  - Keep only postgres job

### 2.2 Manifest Generation Script
- [ ] Create `scripts/generate-manifests.sh`:
  - Generate database manifest using ytt
  - Save to `manifests/generated/instant-cf-phase1-database.yml`
- [ ] Make script executable: `chmod +x scripts/generate-manifests.sh`

### 2.3 Validation
- [ ] Run `./scripts/generate-manifests.sh`
- [ ] Validate with `bosh interpolate manifests/generated/instant-cf-phase1-database.yml`
- [ ] Review generated manifest:
  - Check instance group name: `database`
  - Check job: `postgres`
  - Check static IP: `10.245.0.10`
  - Check database list (cloud_controller, uaa, diego, etc.)

### 2.4 Update Makefile
- [ ] Add `generate-phase1-database` target
- [ ] Update `generate` target to call script

**Deliverable**: Generated database manifest that validates successfully

---

## Milestone 3: First Bob Build (Database)
**Goal**: Build database container with bob  
**Time Estimate**: 2-3 hours + debugging time

### 3.1 Build Script
- [ ] Create `scripts/build-images.sh`:
  - Build database container with bob
  - Tag: `ghcr.io/rkoster/instant-cf-database:latest`

### 3.2 Makefile Integration
- [ ] Add `build-phase1-database` target to Makefile
- [ ] Add bob build command with proper flags

### 3.3 First Build Attempt
- [ ] Run `make build-phase1-database`
- [ ] Document any issues encountered
- [ ] Debug bob issues (may need bob fixes)

### 3.4 Build Validation
- [ ] Verify image created: `docker images | grep instant-cf-database`
- [ ] Inspect image: `docker inspect ghcr.io/rkoster/instant-cf-database:latest`
- [ ] Check image size (should be ~2-3GB)

**Deliverable**: Working database container image

---

## Milestone 4: Phase 1 Runtime Template
**Goal**: Generate runtime (diego-cell) container manifest  
**Time Estimate**: 2-3 hours

### 4.1 Runtime Template
- [ ] Create `manifests/templates/phases/phase1/runtime.yml`:
  - Keep only `diego-cell` instance group
  - Set instances: 1
  - Set network: instant-cf
  - Set static IP: 10.245.0.30
  - Keep all 13 diego-cell jobs

### 4.2 Connection String Updates
- [ ] Update BBS connection to: `10.245.0.20:8889`
- [ ] Update NATS connection to: `10.245.0.20:4222`
- [ ] Update file_server connection to: `10.245.0.20:8080`

### 4.3 Optimizations
- [ ] Set `evacuation_timeout_in_seconds: 0` for rep job
- [ ] Set `set_kernel_parameters: false` for rep job
- [ ] Disable kernel tuning in garden job

### 4.4 Generation and Validation
- [ ] Update `scripts/generate-manifests.sh` to generate runtime manifest
- [ ] Run script and validate output
- [ ] Review generated manifest for correctness

**Deliverable**: Generated runtime manifest with correct networking

---

## Milestone 5: Phase 1 Control Plane Template (Complex)
**Goal**: Generate control plane manifest with ~35 colocated jobs  
**Time Estimate**: 1-2 days

### 5.1 Job Extraction Strategy
- [ ] Document all instance groups to merge:
  - nats (1 job)
  - uaa (3 jobs)
  - singleton-blobstore (2 jobs)
  - api (22 jobs)
  - cc-worker (2 jobs)
  - scheduler (10 jobs - including ssh_proxy from bosh-lite)
  - diego-api (5 jobs)
  - router (2 jobs)
  - tcp-router (2 jobs, optional)
  - doppler (1 job)
  - log-api (4 jobs)
- [ ] Total: ~35-37 jobs

### 5.2 Control Template Implementation
- [ ] Create `manifests/templates/phases/phase1/control.yml`:
  - Use `merge_instance_groups()` from library
  - Create new instance group: `cf-control-plane`
  - Extract and combine all jobs from listed groups
- [ ] Set instances: 1, network: instant-cf, IP: 10.245.0.20

### 5.3 Database Connection Updates
- [ ] Update all jobs that reference `sql-db.service.cf.internal`:
  - Change to: `10.245.0.10`
  - Port: 5524
- [ ] Jobs to update:
  - cloud_controller_ng (api)
  - cloud_controller_worker (cc-worker)
  - cloud_controller_clock (scheduler)
  - cc_deployment_updater (scheduler)
  - uaa
  - bbs (diego-api)
  - locket (diego-api)
  - silk-controller (diego-api)
  - policy-server (api)
  - routing-api (api)
  - credhub (if not skipped)

### 5.4 Blobstore Connection Updates
- [ ] Blobstore is colocated, so connections are localhost
- [ ] Update blobstore routes in cloud_controller_ng
- [ ] Ensure blobstore job binds to correct ports

### 5.5 SSH Proxy Colocation
- [ ] Apply bosh-lite.yml pattern:
  - Remove ssh_proxy from scheduler (it's already handled by bosh-lite.yml)
  - Ensure it's included in merged jobs
  - Verify it ends up on router or scheduler in our merged group

### 5.6 Port Conflict Audit
- [ ] Document all listening ports across 35+ jobs
- [ ] Check for conflicts (jobs listening on same port)
- [ ] Resolve conflicts if any (may need ops file adjustments)

### 5.7 Generation and Validation
- [ ] Update `scripts/generate-manifests.sh` to generate control manifest
- [ ] Run script
- [ ] Validate with `bosh interpolate`
- [ ] Review job count: should be ~35-37 jobs
- [ ] Review properties: ensure all DB/blobstore connections correct

**Deliverable**: Generated control plane manifest with all jobs colocated

---

## Milestone 6: Build All Phase 1 Images
**Goal**: Build control and runtime containers  
**Time Estimate**: 1-2 days (includes debugging)

### 6.1 Build Control Container
- [ ] Add `build-phase1-control` target to Makefile
- [ ] Run `make build-phase1-control`
- [ ] Debug compilation issues (expect issues with 35+ jobs)
- [ ] Document bob behavior with large colocation
- [ ] Iterate on template if needed

### 6.2 Build Runtime Container
- [ ] Add `build-phase1-runtime` target to Makefile
- [ ] Run `make build-phase1-runtime`
- [ ] Debug any issues

### 6.3 Build Optimization
- [ ] Test with compiled releases (should be faster)
- [ ] Document build times for each container
- [ ] Check image sizes

### 6.4 Combined Build Target
- [ ] Add `build-phase1` target that builds all 3 containers
- [ ] Test full build from clean state

**Deliverable**: All 3 Phase 1 container images built successfully

---

## Milestone 7: CLI Tool Foundation
**Goal**: Basic CLI structure and Docker client  
**Time Estimate**: 4-6 hours

### 7.1 Project Structure
- [ ] Create `cmd/icf/main.go` with cobra CLI setup
- [ ] Copy patterns from instant-bosh `cmd/ibosh/main.go`
- [ ] Add version information

### 7.2 Docker Client Library
- [ ] Create `internal/docker/client.go`
- [ ] Copy from instant-bosh and adapt
- [ ] Add methods:
  - `CreateNetwork(name, subnet, gateway)` - Create Docker network
  - `CreateVolume(name)` - Create Docker volume
  - `RemoveVolume(name)` - Remove Docker volume
  - `RunContainer(config)` - Start container with options
  - `StopContainer(name)` - Stop container
  - `RemoveContainer(name)` - Remove container
  - `ContainerStatus(name)` - Get container status
  - `ContainerLogs(name)` - Stream logs

### 7.3 Configuration Management
- [ ] Create `internal/config/config.go`:
  - Define Phase enum (Phase1, Phase2a, Phase2b)
  - Network configuration
  - Image names
  - Volume names

### 7.4 Basic Commands (Stubs)
- [ ] Create `internal/commands/start.go` (stub)
- [ ] Create `internal/commands/stop.go` (stub)
- [ ] Create `internal/commands/destroy.go` (stub)
- [ ] Create `internal/commands/status.go` (stub)
- [ ] Wire up commands in `cmd/icf/main.go`

**Deliverable**: CLI tool that compiles and shows help menu

---

## Milestone 8: Start Command Implementation
**Goal**: Implement `icf start` to launch Phase 1 containers  
**Time Estimate**: 1 day

### 8.1 Network Creation
- [ ] Implement network creation in `start.go`:
  - Name: `instant-cf`
  - Subnet: `10.245.0.0/24`
  - Gateway: `10.245.0.1`
- [ ] Handle case where network already exists

### 8.2 Volume Creation
- [ ] Create volumes:
  - `instant-cf-database-store`
  - `instant-cf-database-data`
  - `instant-cf-control-store`
  - `instant-cf-control-data`
  - `instant-cf-runtime-store`
  - `instant-cf-runtime-data`
- [ ] Handle case where volumes already exist

### 8.3 Database Container Startup
- [ ] Start database container:
  - Name: `instant-cf-database`
  - Image: `ghcr.io/rkoster/instant-cf-database:latest`
  - Network: `instant-cf`, IP: `10.245.0.10`
  - Volumes: store, data
  - Flags: `--rm --privileged`
- [ ] Implement health check: wait for postgres ready
  - Use `pg_isready -h 10.245.0.10 -p 5524`
  - Timeout: 60 seconds
  - Poll interval: 2 seconds

### 8.4 Control Container Startup
- [ ] Start control container:
  - Name: `instant-cf-control`
  - Image: `ghcr.io/rkoster/instant-cf-control:latest`
  - Network: `instant-cf`, IP: `10.245.0.20`
  - Ports: `-p 80:80 -p 443:443 -p 2222:2222 -p 8080:9022`
  - Volumes: store, data
  - Flags: `--rm --privileged`
- [ ] Implement health check: wait for CF API ready
  - Use `curl -k https://api.10.245.0.20.nip.io/v3/info`
  - Timeout: 300 seconds (5 minutes)
  - Poll interval: 5 seconds
- [ ] Stream logs while waiting (show startup progress)

### 8.5 Runtime Container Startup
- [ ] Start runtime container:
  - Name: `instant-cf-runtime`
  - Image: `ghcr.io/rkoster/instant-cf-runtime:latest`
  - Network: `instant-cf`, IP: `10.245.0.30`
  - Volumes: store, data
  - Flags: `--rm --privileged`
- [ ] Implement health check: wait for diego-cell registration
  - Check BBS for registered cells
  - Timeout: 120 seconds
  - Poll interval: 5 seconds

### 8.6 Success Message
- [ ] Print success message with:
  - API URL: `https://api.10.245.0.20.nip.io`
  - Login command: `cf login -a https://api.10.245.0.20.nip.io --skip-ssl-validation`
  - Admin password location: container vars-store
  - Time taken to start

**Deliverable**: Working `icf start` command that launches all 3 containers

---

## Milestone 9: Stop and Destroy Commands
**Goal**: Implement container lifecycle management  
**Time Estimate**: 2-3 hours

### 9.1 Stop Command
- [ ] Implement `internal/commands/stop.go`:
  - Stop containers: runtime, control, database (in reverse order)
  - Keep volumes (for faster restart)
  - Don't remove network
  - Print confirmation

### 9.2 Destroy Command
- [ ] Implement `internal/commands/destroy.go`:
  - Stop containers (call stop logic)
  - Remove volumes (all 6 volumes)
  - Remove network
  - Confirm with user (--force flag to skip)
  - Print what was destroyed

### 9.3 Error Handling
- [ ] Handle case where containers don't exist
- [ ] Handle case where containers are already stopped
- [ ] Handle case where volumes are in use

**Deliverable**: Working `icf stop` and `icf destroy` commands

---

## Milestone 10: Status and Env Commands
**Goal**: Implement status checking and environment helpers  
**Time Estimate**: 3-4 hours

### 10.1 Status Command
- [ ] Implement `internal/commands/status.go`:
  - Check network exists
  - Check containers: database, control, runtime
  - Show container state (running, stopped, not found)
  - Show container uptime
  - Show resource usage (memory, CPU)
  - Show health status for each container
- [ ] Format output nicely (table or colored output)

### 10.2 Env Command
- [ ] Implement `internal/commands/env.go`:
  - Check if control container is running
  - Extract admin password from vars-store:
    - `docker exec instant-cf-control cat /var/vcap/store/vars-store.yml`
    - Parse YAML, get `cf_admin_password`
  - Print environment variables:
    - `export CF_API=https://api.10.245.0.20.nip.io`
    - `export CF_USERNAME=admin`
    - `export CF_PASSWORD=<extracted>`
  - Print usage: `eval "$(icf env)"`

### 10.3 Target Helper
- [ ] Add `--target` flag to `env` command
- [ ] If `--target`, run `cf login` automatically
- [ ] Use extracted credentials

**Deliverable**: Working `icf status` and `icf env` commands

---

## Milestone 11: Logs Command
**Goal**: Stream container logs for debugging  
**Time Estimate**: 2-3 hours

### 11.1 Logs Implementation
- [ ] Implement `internal/commands/logs.go`:
  - Accept container name argument (database, control, runtime, all)
  - Stream logs from specified container
  - If "all", multiplex logs from all 3 containers
  - Add timestamps
  - Add container name prefix for multiplexed logs
- [ ] Add flags:
  - `--follow` (default true) - Follow logs
  - `--since <duration>` - Show logs since duration
  - `--tail <lines>` - Show last N lines

### 11.2 Log Formatting
- [ ] Copy log formatting logic from instant-bosh
- [ ] Color-code by container
- [ ] Highlight errors/warnings

**Deliverable**: Working `icf logs` command

---

## Milestone 12: Integration Testing
**Goal**: End-to-end testing of Phase 1 deployment  
**Time Estimate**: 1 day

### 12.1 Test App Preparation
- [ ] Create `test/fixtures/test-app/`:
  - Simple static app or Go/Node.js app
  - Returns "Hello from instant-cf!"
  - Include manifest.yml

### 12.2 Smoke Test Script
- [ ] Create `scripts/smoke-test.sh`:
  - Start instant-cf (if not running)
  - Wait for API ready
  - Extract admin password
  - `cf login` with admin credentials
  - `cf create-org test`
  - `cf create-space test`
  - `cf target -o test -s test`
  - `cf push test-app` from fixtures
  - Wait for app running
  - `curl https://test-app.apps.10.245.0.20.nip.io`
  - Verify response contains "Hello from instant-cf!"
  - Print success message
- [ ] Make script executable

### 12.3 Manual Testing Checklist
- [ ] Full clean start: `icf destroy && icf start`
- [ ] Check all containers running: `icf status`
- [ ] Run smoke test: `./scripts/smoke-test.sh`
- [ ] Test restart: `icf stop && icf start`
- [ ] Verify vars-store persisted (same admin password)
- [ ] Test logs: `icf logs --tail 100`

### 12.4 Performance Metrics
- [ ] Measure and document:
  - Total memory usage (all containers)
  - Startup time (from `icf start` to API ready)
  - App push time
  - Container image sizes

**Deliverable**: Validated Phase 1 deployment with smoke test passing

---

## Milestone 13: Documentation
**Goal**: Complete documentation for Phase 1  
**Time Estimate**: 4-6 hours

### 13.1 README.md
- [ ] Update `README.md` with:
  - Project description and goals
  - Quick start guide
  - Prerequisites (Docker, devbox)
  - Installation instructions
  - Usage examples (`icf start`, `cf push`)
  - Architecture overview (link to ARCHITECTURE.md)
  - Troubleshooting section
  - License information

### 13.2 Troubleshooting Guide
- [ ] Create `docs/TROUBLESHOOTING.md`:
  - Common issues and solutions
  - Container fails to start → check logs
  - API timeout → increase wait time
  - Memory issues → adjust Docker resources
  - Port conflicts → check other running containers
  - Database connection issues → check network
  - How to collect diagnostics
  - How to file issues

### 13.3 Development Guide
- [ ] Create `docs/DEVELOPMENT.md`:
  - How to set up dev environment
  - How to generate manifests
  - How to build images
  - How to test changes
  - How to add new commands
  - How to modify templates
  - Code organization

### 13.4 Release Checklist
- [ ] Create `docs/RELEASE.md`:
  - Pre-release checklist
  - How to tag releases
  - How to build release binaries
  - How to push images to registry
  - How to write release notes

**Deliverable**: Complete Phase 1 documentation

---

## Milestone 14: Phase 1 Polish and Release
**Goal**: Prepare Phase 1 for release  
**Time Estimate**: 1 day

### 14.1 Code Cleanup
- [ ] Run `go fmt ./...`
- [ ] Run `go vet ./...`
- [ ] Fix any linter warnings
- [ ] Add code comments where needed
- [ ] Remove debug print statements

### 14.2 Testing
- [ ] Test on clean Docker environment
- [ ] Test with limited memory (4GB)
- [ ] Test with slow disk I/O
- [ ] Verify all commands work
- [ ] Run smoke test multiple times

### 14.3 Binary Build
- [ ] Add `build` target to Makefile:
  - `go build -o bin/icf ./cmd/icf`
- [ ] Test binary: `./bin/icf --help`
- [ ] Consider cross-compilation (Linux, macOS, Windows)

### 14.4 Image Publishing
- [ ] Push images to ghcr.io:
  - `docker push ghcr.io/rkoster/instant-cf-database:latest`
  - `docker push ghcr.io/rkoster/instant-cf-control:latest`
  - `docker push ghcr.io/rkoster/instant-cf-runtime:latest`
- [ ] Tag images with version: `v0.1.0`

### 14.5 Release Notes
- [ ] Create release notes for v0.1.0:
  - Phase 1 architecture (3 containers)
  - Features implemented
  - Known limitations
  - Next steps (Phase 2a)

**Deliverable**: Phase 1 release (v0.1.0) published

---

## Milestone 15: Phase 2a Templates (Future)
**Goal**: Two-container architecture  
**Time Estimate**: 1 week

### 15.1 Data Container Template
- [ ] Create `manifests/templates/phases/phase2a/data.yml`:
  - Merge database + singleton-blobstore
  - Single instance group: `cf-data`
  - 2 jobs: postgres + blobstore
  - Static IP: 10.245.0.10

### 15.2 Platform Container Template
- [ ] Create `manifests/templates/phases/phase2a/platform.yml`:
  - Merge control + runtime (all remaining jobs)
  - Single instance group: `cf-platform`
  - ~48 jobs total
  - Static IP: 10.245.0.20
  - Update connections to 10.245.0.10 for DB and blobstore

### 15.3 Build and Test
- [ ] Generate Phase 2a manifests
- [ ] Build both containers
- [ ] Update CLI for Phase 2a
- [ ] Test deployment
- [ ] Document improvements

**Deliverable**: Phase 2a (2 containers) working

---

## Milestone 16: Phase 2b Template (Future)
**Goal**: Single mega-container  
**Time Estimate**: 1 week

### 16.1 All-in-One Template
- [ ] Create `manifests/templates/phases/phase2b/all.yml`:
  - Single instance group: `cf-all`
  - All ~47 jobs colocated
  - All connections to localhost
  - Single IP: 10.245.0.10

### 16.2 Networking Adjustments
- [ ] Update all connection strings to localhost
- [ ] Remove cross-container networking
- [ ] Simplify port mappings

### 16.3 Build and Test
- [ ] Generate Phase 2b manifest
- [ ] Build single container (expect long build time)
- [ ] Update CLI for Phase 2b
- [ ] Test deployment (the moment of truth!)
- [ ] Measure performance

### 16.4 Celebration
- [ ] Document achievement: First single-container CF! 🎉
- [ ] Write blog post
- [ ] Share with CF community

**Deliverable**: Phase 2b (1 container) - THE MEGA-CONTAINER!

---

## Future Enhancements (Backlog)

### Performance Optimizations
- [ ] Pre-rendered templates for faster startup
- [ ] Aggressive caching strategies
- [ ] Parallel job startup

### Features
- [ ] Add CredHub support
- [ ] Add TCP Router support
- [ ] Add Log Cache support
- [ ] Custom SSL certificates
- [ ] ARM64 support for Apple Silicon

### Developer Experience
- [ ] `icf push <dir>` - Helper command
- [ ] `icf apps` - List running apps
- [ ] `icf ssh <container>` - SSH into containers
- [ ] Shell completion (bash/zsh)

### CI/CD
- [ ] GitHub Actions workflow for image builds
- [ ] Automated smoke tests
- [ ] Release automation

---

## Success Criteria Summary

### Phase 1 Success ✅
- 3 containers running (database, control, runtime)
- `cf push` works
- Memory < 6GB
- Startup < 5 minutes
- Documentation complete
- Public release (v0.1.0)

### Phase 2a Success ✅
- 2 containers running (data, platform)
- All Phase 1 tests pass
- Memory < 7GB
- Startup < 7 minutes
- Public release (v0.2.0)

### Phase 2b Success ✅ (Ultimate Goal)
- 1 container running (mega-container!)
- All tests pass
- Memory < 8GB
- Startup < 10 minutes
- First-ever single-container Cloud Foundry!
- Public release (v1.0.0)

---

**Current Status**: Milestone 0 (Bootstrap) - ARCHITECTURE.md and ROADMAP.md created  
**Next Up**: Milestone 0.1 - Repository Initialization  
**Last Updated**: 2024-12-15
