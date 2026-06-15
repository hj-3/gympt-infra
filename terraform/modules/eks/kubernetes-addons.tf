# ============================================
# Kubernetes Addons via Helm and Kubernetes providers
# ============================================
# This file manages essential cluster addons that need to be installed
# immediately after cluster creation

# Data source to wait for cluster to be ready
data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

# ============================================
# Metrics Server
# ============================================
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
  namespace  = "kube-system"

  set {
    name  = "replicas"
    value = "2"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "200Mi"
  }

  depends_on = [
    aws_eks_node_group.general,
    aws_iam_role_policy_attachment.node_policy
  ]
}

# ============================================
# NVIDIA Device Plugin (for GPU nodes)
# ============================================
resource "kubernetes_namespace" "nvidia_device_plugin" {
  count = var.enable_gpu_node_group ? 1 : 0

  metadata {
    name = "nvidia-device-plugin"
    labels = {
      name = "nvidia-device-plugin"
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "helm_release" "nvidia_device_plugin" {
  count = var.enable_gpu_node_group ? 1 : 0

  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.14.5"
  namespace  = kubernetes_namespace.nvidia_device_plugin[0].metadata[0].name

  set {
    name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key"
    value = "nvidia.com/gpu"
  }

  set {
    name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].key"
    value = "nvidia.com/gpu"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [
    aws_eks_node_group.general,
    kubernetes_namespace.nvidia_device_plugin
  ]
}

# ============================================
# AWS Load Balancer Controller
# ============================================
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "enableShield"
    value = "false"
  }

  set {
    name  = "enableWaf"
    value = "false"
  }

  set {
    name  = "enableWafv2"
    value = "false"
  }

  depends_on = [
    aws_eks_node_group.general,
    aws_iam_role_policy_attachment.alb_controller
  ]
}

# ============================================
# Karpenter
# ============================================
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
    labels = {
      name = "karpenter"
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.12.1"
  namespace  = kubernetes_namespace.karpenter.metadata[0].name

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = aws_eks_cluster.main.endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "1"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = "1"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "1Gi"
  }

  set {
    name  = "replicas"
    value = "2"
  }

  depends_on = [
    aws_eks_node_group.general,
    kubernetes_namespace.karpenter
  ]
}

# ============================================
# Karpenter NodePool and EC2NodeClass
# ============================================
resource "kubernetes_manifest" "karpenter_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          alias = "al2023@latest"
        }
      ]
      role = aws_iam_role.node.name
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = aws_eks_cluster.main.name
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = aws_eks_cluster.main.name
          }
        }
      ]
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "100Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 1
        httpTokens              = "required"
      }
      tags = merge(
        var.common_tags,
        {
          Name      = "${local.name_prefix}-karpenter-node"
          ManagedBy = "karpenter"
        }
      )
      userData = <<-EOT
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="BOUNDARY"

        --BOUNDARY
        Content-Type: text/x-shellscript; charset="us-ascii"

        #!/bin/bash
        /etc/eks/bootstrap.sh '${aws_eks_cluster.main.name}' \
          --apiserver-endpoint '${aws_eks_cluster.main.endpoint}' \
          --b64-cluster-ca '${aws_eks_cluster.main.certificate_authority[0].data}'

        --BOUNDARY--
      EOT
    }
  }

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_node_pool_general" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "general"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["t3.medium", "t3.large", "t3.xlarge", "m5.large", "m5.xlarge"]
            }
          ]
          expireAfter = "168h"
        }
      }
      limits = {
        cpu    = var.karpenter_general_cpu_limit
        memory = var.karpenter_general_memory_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "5m"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_node_class]
}

resource "kubernetes_manifest" "karpenter_node_pool_gpu" {
  count = var.enable_gpu_node_group ? 1 : 0

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            gpu              = "true"
            "nvidia.com/gpu" = "true"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          taints = [
            {
              key    = "nvidia.com/gpu"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge", "g5.2xlarge"]
            }
          ]
          expireAfter = "168h"
        }
      }
      limits = {
        cpu              = var.karpenter_gpu_cpu_limit
        memory           = var.karpenter_gpu_memory_limit
        "nvidia.com/gpu" = var.karpenter_gpu_count_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "5m"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_node_class]
}
