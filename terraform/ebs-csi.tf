# ══════════════════════════════════════════════════════════════════════════════
#  EBS CSI Driver
#  Required for PersistentVolumeClaims (PVC) to work on EKS
#  Allows Loki to use EBS gp3 volumes for persistent log storage
# ══════════════════════════════════════════════════════════════════════════════

# ── IAM Trust Policy for EBS CSI Driver ──────────────────────────────────────
data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ── IAM Role for EBS CSI Driver ───────────────────────────────────────────────
resource "aws_iam_role" "ebs_csi" {
  name                  = "${var.project_name}-ebs-csi-role"
  assume_role_policy    = data.aws_iam_policy_document.ebs_csi_trust.json
  force_detach_policies = true

  tags = {
    Name = "${var.project_name}-ebs-csi-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── EKS Add-on: EBS CSI Driver ────────────────────────────────────────────────
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi
  ]

  tags = {
    Name = "${var.project_name}-ebs-csi"
  }
}
