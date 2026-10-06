#!/usr/bin/env ruby

require "yaml"

path = ARGV.fetch(0, "CITATION.cff")
citation = YAML.safe_load(File.read(path), aliases: false)
required = %w[title type version license]
missing = required.reject { |field| citation[field].is_a?(String) && !citation[field].empty? }
abort "Missing citation metadata: #{missing.join(', ')}" unless missing.empty?
abort "Citation must identify software" unless citation["type"] == "software"
abort "Citation must include at least one author" if citation.fetch("authors", []).empty?
abort "Citation version must be semantic (for example 1.0.0)" unless citation["version"].match?(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)

puts "Citation metadata is valid for version #{citation['version']}"
