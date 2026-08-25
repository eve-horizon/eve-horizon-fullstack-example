#!/usr/bin/env ruby

require "pathname"
require "digest"
require "yaml"

root = Pathname.new(__dir__).join("..").expand_path

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

def load_yaml(path)
  YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
rescue Psych::Exception => e
  fail!("#{path}: invalid YAML: #{e.message}")
end

manifest = load_yaml(root.join(".eve/manifest.yaml"))
fail!("manifest must use eve/compose/v2") unless manifest["schema"] == "eve/compose/v2"
fail!("registry must use Eve-native auth") unless manifest["registry"] == "eve"

packs = manifest.dig("x-eve", "packs") || []
factory = packs.find { |pack| pack["source"] == "eve-horizon/eve-software-factory" }
fail!("pinned public software-factory pack missing") unless factory
fail!("software-factory ref must be a full SHA") unless factory["ref"]&.match?(/\A[0-9a-f]{40}\z/)
fail!("manifest still depends on a sibling factory checkout") if packs.any? { |pack| pack["source"].to_s.include?("../eve-software-factory") }

lock = load_yaml(root.join(".eve/packs.lock.yaml"))
locked_factory = lock.fetch("packs", []).find { |pack| pack["id"] == "software-factory" }
fail!("factory lock entry missing") unless locked_factory
fail!("factory lock source/ref drift") unless locked_factory["source"] == factory["source"] && locked_factory["ref"] == factory["ref"]
fail!("effective pack counts drifted") unless lock["effective"].slice("agents_count", "teams_count", "routes_count", "profiles_count") == {
  "agents_count" => 8,
  "teams_count" => 3,
  "routes_count" => 3,
  "profiles_count" => 5
}
fail!("effective pack hashes drifted") unless lock["effective"].slice("agents_hash", "teams_hash", "chat_hash") == {
  "agents_hash" => "208d9052",
  "teams_hash" => "6660768d",
  "chat_hash" => "3e490cc0"
}

vendored_index = load_yaml(root.join(".eve/materialized-skills/index.yaml"))
vendored_factory = vendored_index.fetch("sources", []).find { |source| source["source"] == factory["source"] }
fail!("vendored factory source missing") unless vendored_factory
fail!("vendored factory ref drift") unless vendored_factory["ref"] == factory["ref"]
expected_factory_skills = %w[factory-coder factory-planner factory-pm factory-verifier]
actual_factory_skills = vendored_factory.fetch("skills", []).map { |skill| skill["install_name"] }.sort
fail!("vendored factory skill set drifted") unless actual_factory_skills == expected_factory_skills

vendored_factory.fetch("skills").each do |skill|
  directory = root.join(".eve/materialized-skills", skill.fetch("materialized_path"))
  fail!("vendored skill directory missing: #{directory}") unless directory.directory?
  digest = Digest::SHA256.new
  directory.glob("**/*").select(&:file?).sort.each do |file|
    digest.update(file.relative_path_from(directory).to_s)
    digest.update("\0")
    digest.update(file.binread)
    digest.update("\0")
  end
  fail!("vendored skill hash drift: #{skill['install_name']}") unless "sha256:#{digest.hexdigest}" == skill["content_hash"]
end

services = manifest.fetch("services", {})
%w[api web].each do |name|
  service = services[name] || fail!("#{name} service missing")
  build = service["build"] || fail!("#{name} build missing")
  context = root.join(build["context"])
  dockerfile = root.join(build["dockerfile"])
  fail!("#{name} build context missing") unless context.directory?
  fail!("#{name} Dockerfile missing") unless dockerfile.file?
end

buckets = services.dig("api", "x-eve", "object_store", "buckets") || []
fail!("object-bucket example drifted") unless buckets == [
  { "name" => "uploads", "visibility" => "private" },
  { "name" => "assets", "visibility" => "public" }
]

migration_sources = services.dig("migrate", "x-eve", "files") || []
migration_sources.each do |entry|
  fail!("migration source missing: #{entry['source']}") unless root.join(entry["source"]).directory?
end
fail!("no SQL migrations found") if root.glob("db/migrations/*.sql").empty?
fail!("seed fixture missing") unless root.join("db/seed.sql").file?

(manifest.fetch("pipelines", {}).merge(manifest.fetch("workflows", {}))).each do |name, definition|
  steps = definition.fetch("steps", [])
  step_names = steps.map { |step| step["name"] }.compact
  steps.each do |step|
    executors = %w[action script agent run].count { |key| step.key?(key) }
    fail!("#{name}/#{step['name']}: expected one executor") unless executors == 1
    Array(step["depends_on"]).each do |dependency|
      fail!("#{name}/#{step['name']}: unknown dependency #{dependency}") unless step_names.include?(dependency)
    end
    script = step.dig("script", "run")
    next unless script&.start_with?("./")
    referenced = root.join(script.split.first)
    fail!("#{name}/#{step['name']}: missing script #{referenced}") unless referenced.file?
  end
end

ci_main = manifest.dig("pipelines", "ci-main", "steps") || []
fail!("source-triggered CI must not deploy") if ci_main.any? { |step| step.dig("action", "type") == "deploy" || step.dig("script", "run").to_s.match?(/\beve\s+(env\s+)?deploy\b/) }

%w[package.json apps/api/package-lock.json apps/web/package-lock.json scripts/backup-db.sh scripts/test-api.mjs].each do |relative|
  fail!("missing repository contract: #{relative}") unless root.join(relative).file?
end

root.join("skills.txt").read.each_line do |line|
  source = line.split("#", 2).first.strip
  next if source.empty?
  if source.start_with?("./", "../")
    fail!("skills.txt local source is missing: #{source}") unless root.join(source).exist?
  elsif !source.start_with?("https://github.com/eve-horizon/")
    fail!("skills.txt contains non-canonical remote source: #{source}")
  end
end

puts "Repository validation passed: public pack pin, vendored runtime skills, manifest, pipelines, buckets, migrations and fixtures"
