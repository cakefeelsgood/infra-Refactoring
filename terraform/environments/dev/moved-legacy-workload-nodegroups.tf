# Legacy batch/ai node groups moved into their own module instance so they can be removed
# separately from the Karpenter rollout (enable_dev_legacy_workload_nodegroups). Prevents destroy/recreate.

moved {
  from = module.dev_eks_nodegroups[0].aws_eks_node_group.this["batch_spot"]
  to   = module.dev_eks_legacy_nodegroups[0].aws_eks_node_group.this["batch_spot"]
}

moved {
  from = module.dev_eks_nodegroups[0].aws_launch_template.node_group["batch_spot"]
  to   = module.dev_eks_legacy_nodegroups[0].aws_launch_template.node_group["batch_spot"]
}

moved {
  from = module.dev_eks_nodegroups[0].aws_eks_node_group.this["ai_spot"]
  to   = module.dev_eks_legacy_nodegroups[0].aws_eks_node_group.this["ai_spot"]
}

moved {
  from = module.dev_eks_nodegroups[0].aws_launch_template.node_group["ai_spot"]
  to   = module.dev_eks_legacy_nodegroups[0].aws_launch_template.node_group["ai_spot"]
}
