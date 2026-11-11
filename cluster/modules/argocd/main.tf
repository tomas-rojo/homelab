resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}


resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "10.18.0" # application version v3.2.3
  values = [
    file("${path.module}/values.yaml")
  ]

  depends_on = [kubernetes_namespace_v1.argocd]

}
