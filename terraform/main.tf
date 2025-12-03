terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Optional: Use Terraform Cloud for remote state (free tier)
  # backend "remote" {
  #   organization = "your-org"
  #   workspaces {
  #     name = "cloudops-platform"
  #   }
  # }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-cloudops-cluster"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "kind-cloudops-cluster"
  }
}

# Create monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }
}

# Install Prometheus using Helm
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "54.0.0"

  values = [
    file("${path.module}/values/prometheus-values.yaml")
  ]

  set {
    name  = "prometheus.service.type"
    value = "NodePort"
  }

  set {
    name  = "prometheus.service.nodePort"
    value = "30900"
  }

  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }

  set {
    name  = "grafana.service.nodePort"
    value = "30300"
  }

  set {
    name  = "grafana.adminPassword"
    value = "admin123"
  }
}

# ServiceMonitor for our application
resource "kubernetes_manifest" "app_servicemonitor" {
  depends_on = [helm_release.prometheus]
  
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "cloudops-app-monitor"
      namespace = "cloudops"
      labels = {
        app     = "cloudops-app"
        release = "prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "cloudops-app"
        }
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }
}
