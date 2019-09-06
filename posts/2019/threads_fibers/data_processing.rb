#!/usr/bin/env ruby

#DATA_DIRS = [ "data/2_0", "data/2_1", "data/2_2_up" ]
DATA_DIRS = [ "data/2_0", "data/2_1", "data/2_2_up", "data/2_7" ]
#DATA_DIRS = [ "data/redundant_2_6", "data/2_7" ]

data = {
    "thread_test" => {},
    "fork_test" => {},
    "fiber_test" => {},
    "remastered_fiber_test" => {},
}

def mean(samples)
    samples.inject(0.0, &:+) / samples.size
end

def median(samples)
    sorted = samples.sort
    if samples.size % 2 == 1
        sorted[samples.size / 2]
    else
        (sorted[samples.size / 2] + sorted[samples.size / 2 - 1])/2.0
    end
end

def variance(samples)
    m = mean(samples)
    samples.map { |s| (s - m) * (s - m) }.sum
end

DATA_DIRS.each do |dir|
    Dir["#{dir}/*_err.txt"].each do |file|
        unless file =~ /\A#{dir}\/([a-z_]+)\.rb_([0-9.]+(-p0)?)_iter_(\d+)_w_(\d+)_(\d+)_err.txt\Z/
            raise "Can't parse filename with regexp: #{file.inspect}!"
        end
        test_name = $1
        ruby_ver = $2
        iter_num = $4
        worker_spec = "#{$5} #{$6}"

        err_out = File.read(file)
        unless err_out =~ /(\d+):([0-9.]+)elapsed/
            raise "Can't parse error output: #{file.inspect}!"
        end
        min = $1.to_i
        secs = $2.to_f
        t = min * 60.0 + secs

        data[test_name][ruby_ver] ||= {}
        data[test_name][ruby_ver][worker_spec] ||= {}
        data[test_name][ruby_ver][worker_spec]["iters"] ||= []
        data[test_name][ruby_ver][worker_spec]["iters"].push(t)
    end
end

data.each do |test_name, test_data|
    ruby_vers = test_data.keys.sort
    worker_specs = test_data["2.6.2"].keys.sort_by { |ws| ws.split(" ")[0].to_i }

    worker_specs.each do |ws|
        ruby_vers.each do |rv|
            worker_data = test_data[rv][ws]
            if worker_data
              iters = worker_data["iters"]
              worker_data["median"] = median(worker_data["iters"])
              worker_data["mean"] = mean(worker_data["iters"])
              worker_data["variance"] = variance(worker_data["iters"])

              STDERR.puts "#{test_name} / #{ws} / #{rv} : mean: #{"%.2f" % worker_data["mean"]} median: #{"%.2f" % worker_data["median"]} v: #{"%.2f" % worker_data["variance"]}"
            end
        end
    end
end


#STDERR.puts data.inspect
