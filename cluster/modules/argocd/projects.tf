resource "kubernetes_manifest" "infrastructure_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"

    metadata = {
      name      = "infrastructure"
      namespace = "argocd"
    }

    spec = {
      description = "Infrastructure components"

      sourceRepos = [
        "*"
      ]

      destinations = [
        {
          namespace = "*"
          server    = "https://kubernetes.default.svc"
        }
      ]

      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
    }
  }

  depends_on = [ helm_release.argocd ]

}

resource "kubernetes_manifest" "applications_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"

    metadata = {
      name      = "applications"
      namespace = "argocd"
    }

    spec = {
      description = "Application workloads"

      sourceRepos = [
        "*"
      ]

      destinations = [
        {
          namespace = "*"
          server    = "https://kubernetes.default.svc"
        }
      ]

      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
    }
  }

  depends_on = [ helm_release.argocd ]

}
