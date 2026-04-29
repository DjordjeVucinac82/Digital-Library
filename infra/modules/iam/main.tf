# IAM module — creates all roles needed by the EKS cluster and application pods.
#
# Roles created:
#   1. eks_node_role       — EC2 role for all EKS worker nodes
#   2. compressor_irsa     — IRSA role for compressor pods (SQS send)
#   3. worker_irsa         — IRSA role for worker pods (SQS receive + Secrets Manager)
#   4. lb_controller_irsa  — IRSA role for the AWS Load Balancer Controller
#
# IRSA = IAM Roles for Service Accounts. Pods assume the role via a Kubernetes
# ServiceAccount annotated with the role ARN. The OIDC provider validates the
# pod's identity so only the intended service account can assume the role.

locals {
  # Strips the "https://" prefix from the OIDC URL for use in IAM conditions
  oidc_url = var.oidc_provider_url
}

# ─── EKS Node Role ────────────────────────────────────────────────────────────

# All EC2 instances in both node groups use this role.
resource "aws_iam_role" "eks_node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR read-only: allows nodes to pull Docker images
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─── IRSA: Compressor ─────────────────────────────────────────────────────────

# Compressor can only SEND messages to the books-compressed queue.
# It cannot read, delete, or access any other AWS resource.

resource "aws_iam_role" "compressor_irsa" {
  name = "${var.cluster_name}-compressor-irsa"

  # Trust policy: only the compressor ServiceAccount in the digital-library namespace
  # can assume this role (enforced by the OIDC provider and sub condition)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = "system:serviceaccounts:digital-library:compressor"
        }
      }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_policy" "compressor_sqs" {
  name        = "${var.cluster_name}-compressor-sqs"
  description = "Allow compressor to send messages to the books-compressed SQS queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      Resource = var.sqs_queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "compressor_sqs" {
  role       = aws_iam_role.compressor_irsa.name
  policy_arn = aws_iam_policy.compressor_sqs.arn
}

# ─── IRSA: Worker ─────────────────────────────────────────────────────────────

# Worker can receive/delete from the queue and read the DB secret from Secrets Manager.

resource "aws_iam_role" "worker_irsa" {
  name = "${var.cluster_name}-worker-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = "system:serviceaccounts:digital-library:worker"
        }
      }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_policy" "worker_sqs" {
  name        = "${var.cluster_name}-worker-sqs"
  description = "Allow worker to consume messages from the books-compressed SQS queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      # Allow access to both main queue and DLQ for visibility
      Resource = [var.sqs_queue_arn, var.sqs_dlq_arn]
    }]
  })
}

resource "aws_iam_policy" "worker_secrets" {
  name        = "${var.cluster_name}-worker-secrets"
  description = "Allow worker to read the DB password from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.db_secret_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_sqs" {
  role       = aws_iam_role.worker_irsa.name
  policy_arn = aws_iam_policy.worker_sqs.arn
}

resource "aws_iam_role_policy_attachment" "worker_secrets" {
  role       = aws_iam_role.worker_irsa.name
  policy_arn = aws_iam_policy.worker_secrets.arn
}

# ─── IRSA: AWS Load Balancer Controller ───────────────────────────────────────

# The LB Controller runs inside the cluster and needs broad ELB/EC2 permissions
# to create and manage ALBs from Kubernetes Ingress objects.

resource "aws_iam_role" "lb_controller_irsa" {
  name = "${var.cluster_name}-lb-controller-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          # The LB Controller runs in kube-system namespace
          "${local.oidc_url}:sub" = "system:serviceaccounts:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_policy" "lb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.environment}"
  description = "Allows the AWS Load Balancer Controller to manage ALBs"
  # Load the full standard policy from the JSON file in this module directory
  policy      = file("${path.module}/lb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller_irsa.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ─── IRSA: external-dns ───────────────────────────────────────────────────────

# external-dns watches Kubernetes Ingress objects and automatically creates or
# updates Route 53 A ALIAS records to point to the ALB. It runs in kube-system
# and only needs permissions against the specific hosted zone.

resource "aws_iam_role" "external_dns_irsa" {
  name = "${var.cluster_name}-external-dns-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = "system:serviceaccounts:kube-system:external-dns"
        }
      }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${var.cluster_name}-external-dns"
  description = "Allow external-dns to create and update Route 53 records"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Write permission scoped to the single hosted zone — not all of Route 53
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
      },
      {
        # Read permissions needed to detect drift and list zones
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns_irsa.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# ─── IRSA: Cluster Autoscaler ─────────────────────────────────────────────────

# Cluster Autoscaler runs in kube-system and adjusts the two EKS managed node
# group ASGs in response to Pending pods or underutilised nodes.
#
# Mutating actions (SetDesiredCapacity, TerminateInstance) are scoped via a
# condition tag — the autoscaler can only resize ASGs it owns (tagged in eks/main.tf).
# AWS does not support resource-level restrictions on Describe calls, so those
# actions must remain on Resource "*".

resource "aws_iam_role" "cluster_autoscaler_irsa" {
  name = "${var.cluster_name}-cluster-autoscaler-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = "system:serviceaccounts:kube-system:cluster-autoscaler"
        }
      }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${var.cluster_name}-cluster-autoscaler"
  description = "Allow Cluster Autoscaler to discover and resize EKS managed node group ASGs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Mutating actions scoped to ASGs tagged as owned by this cluster
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        # Read-only discovery — AWS does not support resource-level restrictions here
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler_irsa.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# ─── IRSA: KEDA Operator ──────────────────────────────────────────────────────

# KEDA's operator pod reads SQS queue depth to drive worker pod scaling.
# It needs only read access — no ability to send, receive, or delete messages.
#
# The operator SA is created by the KEDA Helm chart in the keda namespace.
# Setting identityOwner=operator in the ScaledObject tells KEDA to use this
# role directly — no TriggerAuthentication resource is required.

resource "aws_iam_role" "keda_operator_irsa" {
  name = "${var.cluster_name}-keda-operator-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = "system:serviceaccounts:keda:keda-operator"
        }
      }
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_policy" "keda_operator_sqs" {
  name        = "${var.cluster_name}-keda-operator-sqs"
  description = "Allow KEDA operator to read SQS queue depth for worker autoscaling"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      Resource = var.sqs_queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "keda_operator_sqs" {
  role       = aws_iam_role.keda_operator_irsa.name
  policy_arn = aws_iam_policy.keda_operator_sqs.arn
}
