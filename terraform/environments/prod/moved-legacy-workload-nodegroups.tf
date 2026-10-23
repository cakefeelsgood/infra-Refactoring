# Legacy batch/ai node groups moved into their own module instance so they can be removed
# separately from the Karpenter rollout (enable_prod_legacy_workload_nodegroups). Prevents destroy/recreate.

moved {
  from = module.prod_eks_nodegroups[0].aws_eks_node_group.this["batch_on_demand"]
  to   = module.prod_eks_legacy_nodegroups[0].aws_eks_node_group.this["batch_on_demand"]
}

moved {
  from = module.prod_eks_nodegroups[0].aws_launch_template.node_group["batch_on_demand"]
  to   = module.prod_eks_legacy_nodegroups[0].aws_launch_template.node_group["batch_on_demand"]
}

moved {
  from = module.prod_eks_nodegroups[0].aws_eks_node_group.this["batch_spot"]
  to   = module.prod_eks_legacy_nodegroups[0].aws_eks_node_group.this["batch_spot"]
}

moved {
  from = module.prod_eks_nodegroups[0].aws_launch_template.node_group["batch_spot"]
  to   = module.prod_eks_legacy_nodegroups[0].aws_launch_template.node_group["batch_spot"]
}

moved {
  from = module.prod_eks_nodegroups[0].aws_eks_node_group.this["ai_spot"]
  to   = module.prod_eks_legacy_nodegroups[0].aws_eks_node_group.this["ai_spot"]
}

moved {
  from = module.prod_eks_nodegroups[0].aws_launch_template.node_group["ai_spot"]
  to   = module.prod_eks_legacy_nodegroups[0].aws_launch_template.node_group["ai_spot"]
}
