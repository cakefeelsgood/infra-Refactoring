# Static placement check for the On-Demand base + Spot burst strategy.
#
# Builds the node models from the code (managed node groups in terraform/environments/<env>/main.tf,
# Karpenter NodePools in gitops/apps/<env>/karpenter/nodepools.yaml), renders the workloads with
# `helm template`, emulates the capacity-split webhook patch (tools/capacity-split-webhook/patch.go)
# for base and burst pods, and checks where each pod is schedulable:
# nodeSelector, required node affinity and NoSchedule/NoExecute taints vs tolerations.
# CPU/memory capacity and topology spread are not simulated.
#
# Reads only files in this repository; no AWS or cluster access.
# Usage: ruby scripts/validation/check-capacity-placement.rb [env ...]   (default: dev prod)
require "yaml"
require "open3"

ROOT = File.expand_path("../..", __dir__)
ENVS = ARGV.empty? ? %w[dev prod] : ARGV
$failed = false

# ---------- node models ----------

def hcl_block(text, header)
  start = text.index(header) or return ""
  depth = 0
  text[start..].each_char.with_index do |ch, i|
    depth += 1 if ch == "{"
    depth -= 1 if ch == "}"
    return text[start, i + 1] if depth.zero? && ch == "}"
  end
  ""
end

def managed_node_groups(env)
  main = File.read(File.join(ROOT, "terraform/environments/#{env}/main.tf"))
  blocks = ["module \"#{env}_eks_nodegroups\" {", "module \"#{env}_eks_legacy_nodegroups\" {"].map { |h| hcl_block(main, h) }
  blocks.flat_map do |block|
    groups = hcl_block(block, "node_groups = {")
    groups.scan(/^    (\w+) = \{/).flatten.map do |key|
      body = hcl_block(groups, "    #{key} = {")
      labels = hcl_block(body, "labels = {").scan(/(\w+)\s*=\s*"([^"]*)"/).to_h
      taints = body.scan(/key\s*=\s*"([^"]+)"\s*\n\s*value\s*=\s*"([^"]+)"\s*\n\s*effect\s*=\s*"([^"]+)"/).map do |k, v, e|
        { "key" => k, "value" => v, "effect" => e.split("_").map(&:capitalize).join }
      end
      capacity_type = body[/capacity_type\s*=\s*"(\w+)"/, 1]
      labels["eks.amazonaws.com/capacityType"] = capacity_type
      { "name" => "mng:#{key}", "labels" => labels, "taints" => taints }
    end
  end
end

def karpenter_node_pools(env)
  docs = YAML.load_stream(File.read(File.join(ROOT, "gitops/apps/#{env}/karpenter/nodepools.yaml"))).compact
  docs.select { |d| d["kind"] == "NodePool" }.map do |np|
    t = np["spec"]["template"]
    labels = (t.dig("metadata", "labels") || {}).dup
    labels["karpenter.sh/nodepool"] = np["metadata"]["name"]
    ct = t["spec"]["requirements"].find { |r| r["key"] == "karpenter.sh/capacity-type" }
    raise "#{np["metadata"]["name"]}: capacity-type must be a single In value" unless ct && ct["operator"] == "In" && ct["values"].size == 1
    labels["karpenter.sh/capacity-type"] = ct["values"][0]
    { "name" => "karpenter:#{np["metadata"]["name"]}", "labels" => labels, "taints" => t["spec"]["taints"] || [] }
  end
end

# ---------- scheduling predicates ----------

def expr_match?(labels, e)
  v = labels[e["key"]]
  case e["operator"]
  when "In" then e["values"].include?(v)
  when "NotIn" then v.nil? || !e["values"].include?(v)
  when "Exists" then !v.nil?
  when "DoesNotExist" then v.nil?
  when "Gt" then !v.nil? && v.to_i > e["values"][0].to_i
  when "Lt" then !v.nil? && v.to_i < e["values"][0].to_i
  else raise "unsupported operator #{e["operator"]}"
  end
end

def tolerated?(taint, tolerations)
  tolerations.any? do |t|
    key_ok = t["key"].nil? || t["key"].empty? ? t["operator"] == "Exists" : t["key"] == taint["key"]
    val_ok = t["operator"] == "Exists" || t["value"].to_s == taint["value"].to_s
    eff_ok = t["effect"].nil? || t["effect"].empty? || t["effect"] == taint["effect"]
    key_ok && val_ok && eff_ok
  end
end

def schedulable?(spec, node)
  labels = node["labels"]
  return false unless (spec["nodeSelector"] || {}).all? { |k, v| labels[k] == v }
  terms = spec.dig("affinity", "nodeAffinity", "requiredDuringSchedulingIgnoredDuringExecution", "nodeSelectorTerms")
  return false if terms && terms.none? { |term| (term["matchExpressions"] || []).all? { |e| expr_match?(labels, e) } }
  node["taints"].select { |t| %w[NoSchedule NoExecute].include?(t["effect"]) }.all? { |t| tolerated?(t, spec["tolerations"] || []) }
end

# ---------- webhook emulation (tools/capacity-split-webhook/patch.go BuildPatch) ----------

def apply_webhook(spec, role)
  s = Marshal.load(Marshal.dump(spec))
  s["tolerations"] = (s["tolerations"] || []) + [{ "key" => "capacity", "operator" => "Equal", "value" => role == "base" ? "on-demand" : "spot", "effect" => "NoSchedule" }]
  if role == "base"
    e = { "key" => "karpenter.sh/capacity-type", "operator" => "In", "values" => ["on-demand"] }
    na = ((s["affinity"] ||= {})["nodeAffinity"] ||= {})
    req = (na["requiredDuringSchedulingIgnoredDuringExecution"] ||= {})
    terms = req["nodeSelectorTerms"]
    if terms.nil? || terms.empty?
      req["nodeSelectorTerms"] = [{ "matchExpressions" => [e] }]
    else
      terms.each { |t| (t["matchExpressions"] ||= []) << e } # ANDed into every term
    end
  end
  s # burst: only a preferred spot term, which does not restrict placement
end

# ---------- workloads ----------

def render(chart, env, sets = [])
  values = File.join(ROOT, "gitops/values/#{env}/#{chart}-values.yaml")
  args = ["helm", "template", "#{chart}-#{env}", File.join(ROOT, "gitops/charts/#{chart}"), "-f", values] + sets.flat_map { |s| ["--set", s] }
  out, err, st = Open3.capture3(*args)
  raise "helm template #{chart} #{env} failed: #{err}" unless st.success?
  dep = YAML.load_stream(out).compact.find { |d| d["kind"] == "Deployment" }
  dep && dep["spec"]["template"]["spec"]
end

def check(env, label, spec, nodes, expected)
  got = spec ? nodes.select { |n| schedulable?(spec, n) }.map { |n| n["name"] } : []
  ok = got.sort == expected.sort
  $failed ||= !ok
  printf("%-4s [%s] %-58s -> %s%s\n", ok ? "OK" : "FAIL", env, label, got.empty? ? "(nowhere)" : got.join(", "), ok ? "" : "   expected: #{expected.join(", ")}")
end

EXPECTED = {
  "prod" => { "ai-service" => "spot-burst", "batch-job" => "on-demand-base" },
  "dev" => { "ai-service" => "on-demand-base", "batch-job" => "spot-burst" },
}.freeze

ENVS.each do |env|
  mng = managed_node_groups(env)
  pools = karpenter_node_pools(env)
  nodes = mng + pools
  puts "## #{env} nodes"
  nodes.each { |n| puts "     #{n["name"]}: labels=#{n["labels"]} taints=#{n["taints"].map { |t| "#{t["key"]}=#{t["value"]}:#{t["effect"]}" }}" }
  puts "## #{env} placement"

  backend_off = render("backend-api", env)
  backend_on = render("backend-api", env, ["capacitySplit.enabled=true"])
  check(env, "backend-api, capacitySplit off (all base)", backend_off, nodes, ["karpenter:on-demand-base"])
  check(env, "backend-api, capacitySplit on, webhook base pod", apply_webhook(backend_on, "base"), nodes, ["karpenter:on-demand-base"])
  check(env, "backend-api, capacitySplit on, webhook burst pod", apply_webhook(backend_on, "burst"), nodes, ["karpenter:spot-burst"])
  check(env, "backend-api, capacitySplit on, webhook down (fail-open)", backend_on, nodes, ["karpenter:spot-burst"])
  EXPECTED[env].each do |chart, pool|
    check(env, chart, render(chart, env), nodes, ["karpenter:#{pool}"])
  end
  webhook = render("capacity-split-webhook", env, ["image.tag=placement-check"])
  check(env, "capacity-split-webhook controller", webhook, nodes, mng.map { |n| n["name"] }.select { |n| n.include?("ops") })
  # Nothing may depend on the legacy batch/ai node groups once workloads moved (safe to remove).
  legacy = mng.map { |n| n["name"] }.reject { |n| n =~ /core|ops/ }
  [backend_off, apply_webhook(backend_on, "base"), apply_webhook(backend_on, "burst"), render("ai-service", env), render("batch-job", env)].each do |spec|
    hit = legacy.select { |name| schedulable?(spec, nodes.find { |n| n["name"] == name }) }
    next if hit.empty?
    $failed = true
    puts "FAIL [#{env}] a workload can still land on legacy node groups: #{hit.join(", ")}"
  end
  puts "OK   [#{env}] no workload depends on legacy batch/ai node groups (#{legacy.empty? ? "none left" : legacy.join(", ")})"
end

puts($failed ? "RESULT: FAIL" : "RESULT: PASS")
exit($failed ? 1 : 0)
