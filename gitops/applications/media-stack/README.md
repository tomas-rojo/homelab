# media-stack

Kubernetes port of the Docker Compose media stack from
[Pelado-Nerdworks/media-stack](https://github.com/Pelado-Nerdworks/media-stack):
Jellyfin, Sonarr, Radarr, Bazarr, qBittorrent, Jackett, FlareSolverr, Seerr and
Wizarr, running as one Argo CD Application in the `media` namespace.

Every service is rendered from the `bjw-s` **app-template** chart (one Helm
release per app, all pinned to `5.3.0`) with the app-specific values in this
directory. The only hand-written resources are the PVCs and the HTTPRoutes.

## What changed versus the Compose stack

**Caddy is gone.** The homelab terminates ingress with Envoy Gateway and a
wildcard `*.home` certificate, so the whole Caddy layer, its `Caddyfile`, and
the TLS/ACME setup that came with it are not needed.

**Path routing became subdomain routing.** The Compose stack exposed one host
with path prefixes (`/sonarr`, `/radarr`, ...). Here each app gets its own
hostname under the wildcard certificate:

| Service | URL | Backend |
| --- | --- | --- |
| Jellyfin | `https://jellyfin.home` | `jellyfin:8096` |
| Sonarr | `https://sonarr.home` | `sonarr:8989` |
| Radarr | `https://radarr.home` | `radarr:7878` |
| Bazarr | `https://bazarr.home` | `bazarr:6767` |
| qBittorrent | `https://qbittorrent.home` | `qbittorrent:8080` |
| Jackett | `https://jackett.home` | `jackett:9117` |
| Seerr | `https://seerr.home` | `seerr:5055` |
| Wizarr | `https://wizarr.home` | `wizarr:5690` |
| FlareSolverr | *(no route)* | `flaresolverr:8191` (in-cluster only) |

Two nice consequences fall out of this:

- `scripts/configure-base-urls.sh` is not needed. There is no subpath to strip,
  so no app needs a Base URL / UrlBase setting.
- qBittorrent, Jackett and FlareSolverr no longer need dedicated host ports.
  qBittorrent and Jackett get real hostnames, and FlareSolverr stays internal,
  reached as `http://flaresolverr:8191` from Sonarr/Radarr.

**Wizarr uses the upstream image.** The Compose stack ran the `pablokbs/wizarr`
fork because it added `APPLICATION_ROOT` support for `/wizarr`. On a dedicated
hostname the root path is `/`, so the fork is unnecessary.

**Jackett no longer mounts a downloads directory.** Nothing in the stack used
its blackhole folder.

## Layout

```
gitops/applications/media-stack/
├── kustomization.yaml        # namespace, PVCs, routes and the 9 Helm releases
├── pvcs.yaml                 # media-data (RWX) + one config PVC per app
├── http-routes.yaml          # one HTTPRoute per web UI
├── *-values.yaml             # one app-template values file per service
└── README.md
```

The ApplicationSet entry lives in `gitops/appsets/applications.yaml`:

```yaml
- name: media-stack
  namespace: media
```

PVCs use the `longhorn-media` StorageClass
(`gitops/infrastructure/longhorn/storage_class_media.yaml`): expandable,
`Retain` reclaim policy, 2 replicas.

## Storage and the TRaSH layout

The stack keeps the TRaSH Guides folder convention, adapted to Kubernetes:

```
media-data (PVC, ReadWriteMany)
├── torrents/          # qBittorrent writes here
│   ├── movies/
│   ├── series/
│   └── music/
└── media/             # final library, read by Jellyfin/Bazarr
    ├── movies/
    ├── series/
    └── music/
```

Mounts per pod:

| Pod | Mount |
| --- | --- |
| Sonarr, Radarr | whole volume at `/data` |
| qBittorrent | `subPath torrents` at `/data/torrents` |
| Jellyfin, Bazarr | `subPath media` at `/data/media` |
| everything else | no access |

Mounting the whole volume into the *arr apps is what makes imports hardlinks
instead of copies: `/data/torrents` and `/data/media` are on the same
filesystem, so a move is an inode rename. Splitting them into separate PVCs
would silently reintroduce copy + delete.

### Why ReadWriteMany, and the one sharp edge

Five pods share the same volume, so `media-data` is `ReadWriteMany`. Longhorn
implements that with a `share-manager` pod exporting the volume over NFS, which
keeps one filesystem underneath and preserves hardlinks.

The edge: the Longhorn CSI driver only applies `fsGroup` ownership fixes to
`ReadWriteOnce` volumes, so the RWX volume arrives root-owned. That is why the
qBittorrent pod runs an init container as root that creates the directory tree
and chowns the top level to `1000:1000` before anything else starts. The
qBittorrent container itself runs as `PUID=1000` / `PGID=1000`.

### Capacity and replicas

`media-data` requests 200Gi with `numberOfReplicas: "2"`. Longhorn places one
**full replica per node**, so the volume commits **400Gi of raw capacity across
the cluster**, not 200Gi. It is thin-provisioned: real disk usage follows the
actual library size, not the request.

Measured on this cluster (two nodes, `longhorn` disk path `/var/lib/longhorn`):

| Node | Disk | Reserved | Already scheduled |
| --- | --- | --- | --- |
| k8s-cp-01 | 930Gi | 180Gi | 429Gi |
| k8s-wk-01 | 933Gi | 180Gi | 429Gi |

Each node can schedule roughly `930 − 180 = 750Gi` of replicas. After
media-stack, both nodes sit near 629Gi scheduled, leaving about 120Gi per node
for future volumes.

If that headroom is too thin, set `numberOfReplicas: "1"` on the class: media is
re-downloadable, unlike the photo library. Config volumes on the same class keep
`Retain` — the platform default `longhorn` class uses `Delete`, so this class is
deliberately separate rather than reusing it.

## First boot

1. Sync the `media-stack` Application in Argo CD (`media` namespace is created
   automatically).
2. Grab the temporary qBittorrent password:

   ```bash
   kubectl -n media logs deploy/qbittorrent | grep -i 'temporary password'
   ```

   Log in at `https://qbittorrent.home`, change it, then set
   **Tools → Options → Downloads → Default Save Path** to `/data/torrents`.
3. Sonarr (`https://sonarr.home`):
   - Root folder: `/data/media/series`
   - Download client: qBittorrent, host `qbittorrent`, port `8080`
   - Indexers: Torznab feeds from Jackett (`http://jackett:9117`)
   - Indexer proxy: FlareSolverr at `http://flaresolverr:8191/`
4. Radarr (`https://radarr.home`): same, root folder `/data/media/movies`.
5. Bazarr (`https://bazarr.home`): connect Sonarr and Radarr with their API
   keys, folder mapping `/data/media`.
6. Jellyfin (`https://jellyfin.home`): add libraries at `/data/media/movies`,
   `/data/media/series` and `/data/media/music`.
7. Seerr (`https://seerr.home`): connect Jellyfin plus Sonarr/Radarr.
8. Wizarr (`https://wizarr.home`): create invitation links.

The apps persist their state on the config PVCs, so a pod restart or an image
bump keeps every setting.

## Migrating existing data

The Compose stack stored app state in `./config` and media in `./data`. Each app
maps 1:1 onto a config PVC, so migration is a copy per app:

```bash
# 1. Stop the app so nothing writes to its config volume
kubectl -n media scale deploy/sonarr --replicas=0

# 2. Start a throwaway pod that mounts the same PVC
kubectl -n media run pvc-loader --restart=Never --image=alpine \
  --overrides='{"spec":{"containers":[{"name":"pvc-loader","image":"alpine","command":["sleep","3600"],"volumeMounts":[{"name":"config","mountPath":"/config"}]}],"volumes":[{"name":"config","persistentVolumeClaim":{"claimName":"sonarr-config"}}]}}'

# 3. Copy the old settings in, then clean up
kubectl -n media cp ./config/sonarr/. pvc-loader:/config
kubectl -n media delete pod pvc-loader

# 4. Bring the app back
kubectl -n media scale deploy/sonarr --replicas=1
```

| Compose directory | PVC |
| --- | --- |
| `config/sonarr` | `sonarr-config` |
| `config/radarr` | `radarr-config` |
| `config/bazarr` | `bazarr-config` |
| `config/jackett` | `jackett-config` |
| `config/qbittorrent` | `qbittorrent-config` |
| `config/jellyfin` | `jellyfin-config` |
| `config/seerr` (or `jellyseerr`) | `seerr-config` |
| `config/wizarr` | `wizarr-config` |
| `data/torrents`, `data/media` | `media-data` (`torrents/`, `media/`) |

For the library, copy into the `media-data` volume with the same throwaway-pod
technique, or rsync it over NFS from the old host. Keep the originals until the
apps come up with their old settings.

## Operations

- Image tags are pinned per app in `*-values.yaml`; Renovate tracks them because
  the files match `gitops/.+/values\.yaml$`.
- Deployments use `Recreate` (app-template default) because the config volumes
  are `ReadWriteOnce`. Expect a few seconds of downtime per app on update.
- Resources are initial guesses, not measurements. Tune them from the
  kube-prometheus-stack data once the stack has run for a while.
- P2P inbound is not exposed. The torrent port (`6881`) is only inside the
  cluster. If you want peers to dial in, add a `LoadBalancer` Service for that
  port with an address from the MetalLB pool.
- Backups: the config PVCs hold the databases and API keys. The media volume is
  the only copy of the library unless you back it up too.
