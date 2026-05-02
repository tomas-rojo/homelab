# HomeLab

A GitOps-based Kubernetes homelab managed with Terraform and ArgoCD.

## Overview

The cluster is provisioned with Terraform, which also installs and bootstraps ArgoCD. All workloads are then managed through ArgoCD using two ApplicationSets:
- **Infrastructure**: Platform components (MetalLB, cert-manager, Envoy Gateway, Longhorn, CNPG, Sealed Secrets, Prometheus, Grafana, Tailscale)
- **Applications**: User-facing services (Pi-hole, Immich)

## Tech Stack

<table>
    <tr>
        <th>Logo</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/49319725"></td>
        <td><a href="https://k3s.io">K3s</a></td>
        <td>Lightweight Kubernetes distribution</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/selfhst/icons@main/svg/hashicorp-terraform.svg"></td>
        <td><a href="https://www.terraform.io">Terraform</a></td>
        <td>Infrastructure as Code for cluster provisioning</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/30269780"></td>
        <td><a href="https://argoproj.github.io/cd">ArgoCD</a></td>
        <td>GitOps tool to deploy applications to Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://helm.sh/img/helm.svg"></td>
        <td><a href="https://helm.sh">Helm</a></td>
        <td>Package manager for Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSUc5oULW7FJ9qZN5Bn_gg30cNcvj2T4LFQyg&s"></td>
        <td><a href="https://metallb.universe.tf">MetalLB</a></td>
        <td>Load balancer for bare metal Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://github.com/jetstack/cert-manager/raw/master/logo/logo.png"></td>
        <td><a href="https://cert-manager.io">cert-manager</a></td>
        <td>Cloud native certificate management</td>
    </tr>
    <tr>
        <td><img width="32" src="https://assets.streamlinehq.com/image/private/w_300,h_300,ar_1/f_auto/v1/icons/3/envoy-6ycf61wbliq2a9l2gf061z.png/envoy-rzwegeuxv8mtrwxuorx67.png?_a=DATAiZAAZAA0"></td>
        <td><a href="https://gateway.envoy.io">Envoy Gateway</a></td>
        <td>Kubernetes Gateway API</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn.jsdelivr.net/gh/selfhst/icons@main/png/rancher-longhorn.png"></td>
        <td><a href="https://longhorn.io">Longhorn</a></td>
        <td>Cloud-native block storage for Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/48932923?s=200&v=4"></td>
        <td><a href="https://tailscale.com">Tailscale</a></td>
        <td>VPN without port forwarding</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cloudnative-pg.io/images/hero_image.svg"></td>
        <td><a href="https://cloudnative-pg.io">CloudNative PG</a></td>
        <td>PostgreSQL operator for Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cdn-blog.lawrencemcdaniel.com/wp-content/uploads/2023/04/23063353/k8s-secret.jpg"></td>
        <td><a href="https://github.com/bitnami-labs/sealed-secrets">Sealed Secrets</a></td>
        <td>Encrypted Kubernetes secrets for Git</td>
    </tr>
    <tr>
        <td><img width="32" src="https://avatars.githubusercontent.com/u/3380462"></td>
        <td><a href="https://prometheus.io">Prometheus</a></td>
        <td>Systems monitoring and alerting toolkit</td>
    </tr>
    <tr>
        <td><img width="32" src="https://grafana.com/static/assets/img/grafana_logo.svg"></td>
        <td><a href="https://grafana.com">Grafana</a></td>
        <td>Observability platform</td>
    </tr>
</table>

## Key Details

- MetalLB LoadBalancer IP range: 192.168.1.230–239
- Ingress: Wildcard TLS (*.home) via Envoy Gateway
- Storage: Longhorn with 2 replicas by default

## Quick Links

- [AGENTS.md](./AGENTS.md) - Detailed development documentation
- [cluster/](./cluster/) - Terraform for cluster provisioning
- [gitops/](./gitops/) - ArgoCD application definitions