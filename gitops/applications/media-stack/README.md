# media-stack

One Argo CD Application in the `media` namespace: Jellyfin, Sonarr, Radarr,
Bazarr, qBittorrent, Jackett, FlareSolverr, Seerr and Wizarr.

Every service is rendered from the `bjw-s` **app-template** chart (one Helm
release per app, all pinned to `5.3.0`) with the app-specific values in this
directory. The only hand-written resources are the PVCs and the HTTPRoutes.

## Services

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

Each app gets its own hostname under the wildcard `*.home` certificate, so no
app needs a Base URL / subpath setting, and qBittorrent, Jackett and FlareSolverr
need no dedicated host ports. FlareSolverr is reached from Sonarr/Radarr as
`http://flaresolverr:8191`.

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

## Storage

`media-data` is one `ReadWriteMany` volume following the TRaSH layout:

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

Longhorn implements RWX with a `share-manager` pod exporting the volume over
NFS, which keeps one filesystem underneath and preserves hardlinks. Two
consequences:

- **The RWX volume arrives root-owned.** The Longhorn CSI driver only applies
  `fsGroup` fixes to `ReadWriteOnce` volumes, so qBittorrent runs an init
  container as root that creates the directory tree and chowns the top level to
  `1000:1000`; the container itself runs as `PUID=1000` / `PGID=1000`.
- **Every node that mounts it needs an NFS client.** `nfs-common` is installed on
  the worker node, which is the only node running these pods.

### One replica, on the worker node

All volumes use the `longhorn-media` StorageClass
(`gitops/infrastructure/longhorn/storage_class_media.yaml`):

```yaml
numberOfReplicas: "1"
nodeSelector: "media"     # Longhorn node tag, only on k8s-wk-01
reclaimPolicy: Retain
allowVolumeExpansion: true
```

So the library and every config volume live on `k8s-wk-01` only: 200Gi requested
for `media-data` is 200Gi of raw capacity, not 2 × 200Gi. The tag is a
prerequisite and is not in Git (the `Node` CR belongs to longhorn-manager):

```bash
kubectl -n longhorn-system patch nodes.longhorn.io k8s-wk-01 \
  --type merge -p '{"spec":{"tags":["media"]}}'
```

Without the tag, new volumes stay `Pending` with no obvious reason.

The trade-off is real: one copy means losing the worker makes the library and the
config volumes unavailable until it returns. Media is re-downloadable; the config
PVCs (SQLite databases, Jellyfin metadata, API keys) are not — back those up.

## Ingress and DNS

The apps are exposed through the existing Envoy Gateway and wildcard
certificate. The hostnames are also added to Pi-hole's `custom.list`
(`gitops/applications/pihole/local-dns-cm.yaml`).

That ConfigMap is mounted with `subPath`, and `subPath` mounts never refresh in
place: after changing the DNS entries, restart Pi-hole or the running pod keeps
serving the old file.

```bash
kubectl -n pihole rollout restart deploy/pihole
```

## First boot

The apps persist their state on the config PVCs, so a pod restart or an image
bump keeps every setting. Initial configuration, in order:

1. Sync the `media-stack` Application in Argo CD (`media` is created for you).
2. qBittorrent — grab the temporary password, log in, change it, then set
   **Tools → Options → Downloads → Default Save Path** to `/data/torrents`:

   ```bash
   kubectl -n media logs deploy/qbittorrent | grep -i 'temporary password'
   ```

3. Sonarr — root folder `/data/media/series`; download client qBittorrent at
   `qbittorrent:8080`; indexers from Jackett at `http://jackett:9117`; indexer
   proxy FlareSolverr at `http://flaresolverr:8191/`.
4. Radarr — same, root folder `/data/media/movies`.
5. Bazarr — connect Sonarr and Radarr with their API keys, folder mapping
   `/data/media`.
6. Jellyfin — add libraries at `/data/media/movies`, `/data/media/series` and
   `/data/media/music`.
7. Seerr — connect Jellyfin plus Sonarr/Radarr.
8. Wizarr — create invitation links.

## Operations

- Image tags are pinned per app in `*-values.yaml`; Renovate tracks them because
  the files match `gitops/.+/values\.yaml$`.
- Deployments use `Recreate` (app-template default) because the config volumes
  are `ReadWriteOnce`. Expect a few seconds of downtime per app on update.
- Resources are initial guesses, not measurements. Tune them from the
  kube-prometheus-stack data once the stack has run for a while.
- P2P inbound is not exposed: the torrent port (`6881`) is only inside the
  cluster. To let peers dial in, add a `LoadBalancer` Service for that port with
  an address from the MetalLB pool.
