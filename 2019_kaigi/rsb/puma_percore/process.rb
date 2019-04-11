#!/usr/bin/env ruby

# This is a simple Ruby data processing library for (specifically)
# use with RSB. There's a similar but different one for RRB.
#
# For simple use, you can either use the default cohorts, which
# group by the Ruby version, the URL, the server command and
# the amount of time benchmarked. In some cases you'll want to
# provide a different division into cohorts.
#
# In my canonical benchmarking, a "normal" run tends to have an
# error rate of zero in 180 seconds. So if you're seeing anything
# that exceeds the threshold here (0.01%, or 1 per 10k requests),
# something's up.

require "json"
require "optparse"

cohorts_by = "rvm current,warmup_seconds,benchmark_seconds,server_cmd,url"
input_glob = "rsb_*.json"
error_proportion = 0.0001  # Default to 0.01% of requests in any single file may have an error
permissive_cohorts = false
include_raw_data = false

OptionParser.new do |opts|
  opts.banner = "Usage: ruby process.rb [options]"
  opts.on("-c", "--cohorts-by COHORTS", "Comma-separated variables to partition data by, incl. RUBY_VERSION,warmup_iterations,etc.") do |c|
    cohorts_by = c
  end
  opts.on("-i", "--input-glob GLOB", "File pattern to match on (default #{input_glob})") do |s|
    input_glob = s
  end
  opts.on("-e PROPORTION", "--error-tolerance PROPORTION", "Error tolerance in analysis as a proportion of requests per data file -- defaults to 0.0001, or 0.01% of requests in a particular file may have an error.") do |p|
    error_proportion = p.to_f
  end
  opts.on("-p", "--permissive-cohorts", "Allow cohort components to be NULL for a particular file or sample") do
    permissive_cohorts = true
  end
  opts.on("--include-raw-data", "Include all latencies in final output file") do
    include_raw_data = true
  end
end.parse!

OUTPUT_FILE = "process_output.json"

cohort_indices = cohorts_by.strip.split(",")

req_time_by_cohort = {}
req_rates_by_cohort = {}
throughput_by_cohort = {}
errors_by_cohort = {}

INPUT_FILES = Dir[input_glob]

process_output = {
  cohort_indices: cohort_indices,
  input_files: INPUT_FILES,
  #req_time_by_cohort: req_time_by_cohort,
  throughput_by_cohort: throughput_by_cohort,
  #startup_by_cohort: startup_by_cohort,
  processed: {
    :cohort => {},
  },
}

# wrk encodes its arrays as (value, count) pairs, which get
# dumped into a long single array by wrk_bench. This method
# reencodes as simple Ruby arrays.
def run_length_array_to_simple_array(input)
  out = []

  input.each_slice(2) do |val, count|
    out.concat([val] * count)
  end
  out
end

error_total = 0

INPUT_FILES.each do |f|
  begin
    d = JSON.load File.read(f)
  rescue JSON::ParserError
    raise "Error parsing JSON in file: #{f.inspect}"
  end

  # Assign a cohort to these samples
  cohort_parts = cohort_indices.map do |cohort_elt|
    raise "Unexpected file format for file #{f.inspect}!" unless d && d["settings"] && d["environment"]
    item = nil
    if d["settings"].has_key?(cohort_elt)
      item = d["settings"][cohort_elt]
    elsif d["environment"].has_key?(cohort_elt)
      item = d["environment"][cohort_elt]
    else
      if permissive_cohorts
        cohort_elt = ""
      else
        raise "Can't find setting or environment object #{cohort_elt} in file #{f.inspect}!"
      end
    end
    item
  end
  cohort = cohort_parts.join(",")

  # Reject incorrect versions of data format
  if d["version"] != "wrk:2"
    raise "Unrecognized data version #{d["version"].inspect} in JSON file #{f.inspect}!"
  end

  latencies = run_length_array_to_simple_array d["requests"]["benchmark"]["latencies"]
  req_rates = run_length_array_to_simple_array d["requests"]["benchmark"]["req_per_sec"]
  errors = d["requests"]["benchmark"]["errors"]

  if errors.values.any? { |e| e > 0 }
    errors_in_file = errors.values.inject(0, &:+)
    error_total += errors_in_file
    error_rate = errors_in_file.to_f / latencies.size
    if error_rate > error_proportion
      raise "Error rate of #{error_rate.inspect} exceeds maximum of #{error_proportion}! Raise the maximum with -e or throw away file #{f.inspect}!"
    end
  end

  duration = d["settings"]["benchmark_seconds"]
  if duration.nil? || duration < 0.00001
    raise "Problem with duration (#{duration.inspect}), file #{f.inspect}, cohort #{cohort.inspect}"
  end

  req_time_by_cohort[cohort] ||= []
  req_time_by_cohort[cohort].concat latencies

  req_rates_by_cohort[cohort] ||= []
  req_rates_by_cohort[cohort].concat req_rates

  throughput_by_cohort[cohort] ||= []
  throughput_by_cohort[cohort].push (latencies.size.to_f / duration)

  errors_by_cohort[cohort] ||= []
  errors_by_cohort[cohort].push errors
end

def percentile(list, pct)
  len = list.length
  how_far = pct * 0.01 * (len - 1)
  prev_item = how_far.to_i
  return list[prev_item] if prev_item >= len - 1
  return list[0] if prev_item < 0

  linear_combination = how_far - prev_item
  list[prev_item] + (list[prev_item + 1] - list[prev_item]) * linear_combination
end

def array_mean(arr)
  return nil if arr.empty?
  arr.inject(0.0, &:+) / arr.size
end

# Calculate variance based on the Wikipedia article of algorithms for variance.
# https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
# Includes Bessel's correction.
def array_variance(arr)
  n = arr.size
  return nil if arr.empty? || n < 2

  ex = ex2 = 0.0
  arr0 = arr[0].to_f
  arr.each do |x|
    diff = x - arr0
    ex += diff
    ex2 += diff * diff
  end

  (ex2 - (ex * ex) / arr.size) / (arr.size - 1)
end

req_time_by_cohort.keys.sort.each do |cohort|
  latencies = req_time_by_cohort[cohort].map { |num| num / 1_000_000.0 }.sort
  rates = req_rates_by_cohort[cohort].sort
  throughputs = throughput_by_cohort[cohort].sort

  cohort_printable = cohort_indices.zip(cohort.split(",")).map { |a, b| "#{a}: #{b}" }.join(", ")
  print "=====\nCohort: #{cohort_printable}, # of requests: #{latencies.size} http requests, #{throughputs.size} batches\n"

  process_output[:processed][:cohort][cohort] = {
    request_percentiles: {},
    rate_percentiles: {},
    throughputs: throughputs,
  }
  if include_raw_data
    process_output[:processed][:cohort][cohort][:latencies] = latencies
    process_output[:processed][:cohort][cohort][:request_rates] = rates
  end
  print "--\n  Request latencies:\n"
  (0..100).each do |p|
    process_output[:processed][:cohort][cohort][:request_percentiles][p.to_s] = percentile(latencies, p)
    print "  #{"%2d" % p}%ile: #{percentile(latencies, p)}\n" if p % 5 == 0
  end
  variance = array_variance(latencies)
  print "  Mean: #{array_mean(latencies).inspect} Median: #{percentile(latencies, 50).inspect} Variance: #{variance.inspect} StdDev: #{Math.sqrt(variance).inspect}\n"
  process_output[:processed][:cohort][cohort][:latency_mean] = array_mean(latencies)
  process_output[:processed][:cohort][cohort][:latency_median] = percentile(latencies, 50)
  process_output[:processed][:cohort][cohort][:latency_variance] = variance

  print "--\n  Requests/Second Rates:\n"
  (0..20).each do |i|
    p = i * 5
    process_output[:processed][:cohort][cohort][:rate_percentiles][p.to_s] = percentile(rates, p)
    print "  #{"%2d" % p}%ile: #{percentile(rates, p)}\n"
  end
  variance = array_variance(rates)
  print "  Mean: #{array_mean(rates).inspect} Median: #{percentile(rates, 50).inspect} Variance: #{variance.inspect} StdDev: #{Math.sqrt(variance).inspect}\n"
  process_output[:processed][:cohort][cohort][:rate_mean] = array_mean(rates)
  process_output[:processed][:cohort][cohort][:rate_median] = percentile(rates, 50)
  process_output[:processed][:cohort][cohort][:rate_variance] = array_variance(rates)

  print "--\n  Throughput in reqs/sec for each full run:\n"
  if throughputs.size == 1
    # Only one run means no variance or standard deviation
    print "  Mean: #{array_mean(throughputs).inspect} Median: #{percentile(throughputs, 50).inspect}\n"
    process_output[:processed][:cohort][cohort][:throughput_mean] = array_mean(throughputs)
    process_output[:processed][:cohort][cohort][:throughput_median] = percentile(throughputs, 50)
    process_output[:processed][:cohort][cohort][:throughput_variance] = array_variance(throughputs)
  else
    variance = array_variance(throughputs)
    print "  Mean: #{array_mean(throughputs).inspect} Median: #{percentile(throughputs, 50).inspect} Variance: #{variance} StdDev: #{Math.sqrt(variance)}\n"
    process_output[:processed][:cohort][cohort][:throughput_mean] = array_mean(throughputs)
    process_output[:processed][:cohort][cohort][:throughput_median] = percentile(throughputs, 50)
    process_output[:processed][:cohort][cohort][:throughput_variance] = variance
  end
  print "  #{throughputs.inspect}\n\n"

  print "--\n  Error rates:\n"
  errors_by_type = {
    "connect" => 0,
    "read" => 0,
    "write" => 0,
    "status" => 0,
    "timeout" => 0,
  }
  errors_by_cohort[cohort].each { |e| e.each { |k, v| errors_by_type[k] += v }}
  error_total = errors_by_cohort[cohort].map { |e| e.values.inject(0, &:+) }.inject(0, &:+)
  process_output[:processed][:cohort][cohort][:error_total] = error_total
  process_output[:processed][:cohort][cohort][:error_rate] = error_total.to_f / latencies.size
  process_output[:processed][:cohort][cohort][:errors_by_type] = errors_by_type

  print "  Cohort rate: #{error_total.to_f / latencies.size}, cohort total errors: #{error_total}\n"
  print "  By type:\n"
  print "    Connect: #{errors_by_type["connect"]}\n"
  print "    Read: #{errors_by_type["read"]}\n"
  print "    Write: #{errors_by_type["write"]}\n"
  print "    HTTP Status: #{errors_by_type["status"]}\n"
  print "    Timeout: #{errors_by_type["timeout"]}\n"
  print "\n\n"
end

print "******************\n"

File.open(OUTPUT_FILE, "w") do |f|
  f.print JSON.pretty_generate(process_output)
end
