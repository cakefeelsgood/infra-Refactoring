# Static check: names that ArgoCD manifests hard-code must match what Terraform creates.
# ArgoCD cannot read Terraform outputs, so the Karpenter controller IRSA role, node role,
# interruption queue, cluster name/discovery tag and webhook ECR repository are written as
# literals in gitops/. A typo there only shows up after apply + sync (controller AccessDenied,
# EC2NodeClass not Ready, ImagePullBackOff). This compares both sides from the code.
#
# Reads only files in this repository; no AWS or cluster access.
# Usage: ruby scripts/validation/check-karpenter-wiring.rb [env ...]   (default: dev prod)
require "yaml"

ROOT = File.expand_path("../..", __dir__)
ENVS = ARGV.empty? ? %w[dev prod] : ARGV
$failed = false

def read(path)
  File.read(File.join(ROOT, path))
end

def var_default(env, name)
  text = read("terraform/environments/#{env}/variables.tf")
  block = text[/variable "#{name}" \{.*?\n\}/m] or raise "#{env}: variable #{name} not found"
  block[/default\s*=\s*"([^"]*)"/, 1] or raise "#{env}: variable #{name} has no string default"
end

def module_local(name, name_prefix)
  expr = read("terraform/modules/karpenter/main.tf")[/^\s*#{name}\s*=\s*"([^"]+)"/, 1] or raise "local #{name} not found"
  expr.gsub("${local.name_prefix}", name_prefix)
end

def module_var_default(name)
  read("terraform/modules/karpenter/variables.tf")[/variable "#{name}" \{.*?default\s*=\s*"([^"]+)"/m, 1]
end

def check(env, what, expected, actual)
  ok = expected == actual
  $failed ||= !ok
  printf("%-4s [%s] %-52s %s\n", ok ? "OK" : "FAIL", env, what, ok ? actual.inspect : "expected #{expected.inspect}, got #{actual.inspect}")
end

ENVS.each do |env|
  project = var_default(env, "project_name")
  cluster = var_default(env, "#{env}_eks_cluster_name")
  prefix = "#{project}-#{env}"
  main = read("terraform/environments/#{env}/main.tf")
  karpenter_tf = read("terraform/environments/#{env}/karpenter.tf")

  # Terraform side wiring
  check(env, "karpenter module environment", env, karpenter_tf[/environment\s*=\s*"(\w+)"/, 1])
  check(env, "karpenter module cluster_name", "module.#{env}_eks[0].cluster_name", karpenter_tf[/cluster_name\s*=\s*(\S+)/, 1])
  check(env, "eks module cluster_name variable", "var.#{env}_eks_cluster_name", main[/module "#{env}_eks" \{.*?cluster_name\s*=\s*(\S+)/m, 1])
  check(env, "vpc module discovery-tag cluster variable", "var.#{env}_eks_cluster_name", main[/module "#{env}_vpc" \{.*?eks_cluster_name\s*=\s*(\S+)/m, 1])

  # EC2NodeClass
  nc = YAML.load_file(File.join(ROOT, "gitops/apps/#{env}/karpenter/ec2nodeclass.yaml"))
  check(env, "EC2NodeClass spec.role", module_local("node_role_name", prefix), nc["spec"]["role"])
  check(env, "EC2NodeClass subnet discovery tag", cluster, nc["spec"]["subnetSelectorTerms"][0]["tags"]["karpenter.sh/discovery"])
  check(env, "EC2NodeClass security group discovery tag", cluster, nc["spec"]["securityGroupSelectorTerms"][0]["tags"]["karpenter.sh/discovery"])

  # Karpenter controller Application
  app = YAML.load_file(File.join(ROOT, "gitops/argocd/#{env}/applications/karpenter-#{env}.yaml"))
  values = YAML.safe_load(app["spec"]["source"]["helm"]["values"])
  check(env, "Karpenter settings.clusterName", cluster, values.dig("settings", "clusterName"))
  check(env, "Karpenter settings.interruptionQueue", module_local("queue_name", prefix), values.dig("settings", "interruptionQueue"))
  role_arn = values.dig("serviceAccount", "annotations", "eks.amazonaws.com/role-arn").to_s
  check(env, "Karpenter IRSA role name", module_local("controller_role_name", prefix), role_arn[%r{:role/(.+)\z}, 1])
  check(env, "Karpenter ServiceAccount name (IRSA trust)", module_var_default("controller_service_account_name"), values.dig("serviceAccount", "name"))
  check(env, "Karpenter namespace (IRSA trust)", module_var_default("controller_namespace"), app["spec"]["destination"]["namespace"])

  # capacity-split webhook image repository
  ecr = main[/capacity-split-webhook = \{\s*name\s*=\s*"([^"]+)"/m, 1].to_s.gsub("${var.project_name}", project)
  repo = YAML.load_file(File.join(ROOT, "gitops/values/#{env}/capacity-split-webhook-values.yaml")).dig("image", "repository").to_s
  check(env, "webhook image repository (ECR name)", ecr, repo.split("/").last)
end

puts($failed ? "RESULT: FAIL" : "RESULT: PASS")
exit($failed ? 1 : 0)
