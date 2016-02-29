require 'spec_helper'
require 'date'

describe 'metrics', :skip_metrics => true do

  before(:all) do
    @number_of_nodes = 1
    @outFile = Tempfile.new('smetrics')

    @pid = spawn(
      {
        'DOPPLER_ADDR' => doppler_address,
        'CF_ACCESS_TOKEN' => cf.auth_token
      },
      'firehose_sample',
      [:out, :err] => [@outFile.path, 'w']
    )
  end

  after(:all) do
    Process.kill("INT", @pid)
    @outFile.unlink
  end

  describe 'rabbitmq haproxy metrics' do
    it 'contains haproxy_z1 metric for rabbitmq haproxy nodes' do
      assert_metric('/p-rabbitmq/haproxy/heartbeat', 'haproxy_z1', 0, /value:1 unit:"boolean"/)
    end

    context 'when haproxy_z1 is not running' do
      before(:all) do
        @ha_host = bosh_director.ips_for_job('haproxy_z1', environment.bosh_manifest.deployment_name)[0]
        ssh_gateway.execute_on(@ha_host, '/var/vcap/bosh/bin/monit stop rabbitmq-haproxy', :root => true)
      end

      after(:all) do
        ssh_gateway.execute_on(@ha_host, '/var/vcap/bosh/bin/monit start rabbitmq-haproxy', :root => true)
      end

      it 'contains haproxy_z1 metrics for rabbitmq haproxy nodes' do
        assert_metric('/p-rabbitmq/haproxy/heartbeat', 'haproxy_z1', 0, /value:0 unit:"boolean"/)
      end
    end
  end

  describe 'rabbitmq server metrics' do
    it 'contains rmq_z1 heartbeat node metrics' do
      assert_metric('/p-rabbitmq/rabbitmq/heartbeat', 'rmq_z1', 0, /value:1 unit:"boolean"/)
    end

    it 'contains rmq_z1 process count metrics' do
      assert_metric('/p-rabbitmq/rabbitmq/erlang/erlang_processes', 'rmq_z1', 0, /value:[1-9][0-9]* unit:"count"/)
    end

    context 'when rmq_z1 is not running' do
      before(:all) do
        @rmq_z1_host = bosh_director.ips_for_job('rmq_z1', environment.bosh_manifest.deployment_name)[0]
        ssh_gateway.execute_on(@rmq_z1_host, '/var/vcap/bosh/bin/monit stop rabbitmq-server', :root => true)
      end

      after(:all) do
        ssh_gateway.execute_on(@rmq_z1_host, '/var/vcap/bosh/bin/monit start rabbitmq-server', :root => true)
      end

      it 'contains rmq_z1 heartbeat node metrics' do
        assert_metric('/p-rabbitmq/rabbitmq/heartbeat', 'rmq_z1', 0, /value:0 unit:"boolean"/)
      end

      it 'contains rmq_z1 process count metrics' do
        assert_metric('/p-rabbitmq/rabbitmq/erlang/erlang_processes', 'rmq_z1', 0, /value:0 unit:"count"/)
      end
    end

    it 'contains the heartbeat metrics for all RabbitMQ nodes' do
      assert_metric('/p-rabbitmq/rabbitmq/heartbeat', 'rmq_z1', 0, /value:1 unit:"boolean"/)
      assert_metric('/p-rabbitmq/rabbitmq/heartbeat', 'rmq_z2', 0, /value:1 unit:"boolean"/)
    end

    context 'when all RabbitMQ nodes are not running' do
      before(:all) do
        @rmq_z1_host = bosh_director.ips_for_job('rmq_z1', environment.bosh_manifest.deployment_name)[0]
        @rmq_z2_host = bosh_director.ips_for_job('rmq_z2', environment.bosh_manifest.deployment_name)[0]

        ssh_gateway.execute_on(@rmq_z1_host, '/var/vcap/bosh/bin/monit stop rabbitmq-server', :root => true)
        ssh_gateway.execute_on(@rmq_z2_host, '/var/vcap/bosh/bin/monit stop rabbitmq-server', :root => true)
      end

      after(:all) do
        ssh_gateway.execute_on(@rmq_z1_host, '/var/vcap/bosh/bin/monit start rabbitmq-server', :root => true)
        ssh_gateway.execute_on(@rmq_z2_host, '/var/vcap/bosh/bin/monit start rabbitmq-server', :root => true)
      end

      it 'contains rmq_z1 and rmq_z2 heartbeat node metrics' do
        assert_metric('/p-rabbitmq/rabbitmq/heartbeat', 'rmq_z1', 0, /value:0 unit:"boolean"/)
        assert_metric('/p-rabbitmq/rabbitmq/heartbeat', 'rmq_z2', 0, /value:0 unit:"boolean"/)
      end

      it 'contains rmq_z1 and rmq_z2 process count metrics' do
        assert_metric('/p-rabbitmq/rabbitmq/erlang/erlang_processes', 'rmq_z1', 0, /value:0 unit:"count"/)
        assert_metric('/p-rabbitmq/rabbitmq/erlang/erlang_processes', 'rmq_z2', 0, /value:0 unit:"count"/)
      end
    end
  end

  describe 'rabbitmq broker metrics' do
    it 'contains rmq-broker node metrics' do
      assert_metric('/p-rabbitmq/service_broker/heartbeat', 'rmq-broker', 0, /value:1 unit:"boolean"/)
    end

    context 'when rmq-broker is not running' do
      before(:all) do
        @rmq_broker_host = bosh_director.ips_for_job('rmq-broker', environment.bosh_manifest.deployment_name)[0]
        ssh_gateway.execute_on(@rmq_broker_host, '/var/vcap/bosh/bin/monit stop rabbitmq-broker', :root => true)
      end

      after(:all) do
        ssh_gateway.execute_on(@rmq_broker_host, '/var/vcap/bosh/bin/monit start rabbitmq-broker', :root => true)
      end

      it 'contains rmq-broker node metrics' do
        assert_metric('/p-rabbitmq/service_broker/heartbeat', 'rmq-broker', 0, /value:0 unit:"boolean"/)
      end
    end
  end

  def assert_metric(metric_name, job_name, job_index, *regex_patterns)
    metric = find_metric(metric_name, job_name, job_index)

    expect(metric).to match(/value:\d/)
    expect(metric).to include('origin:"rmq"')
    expect(metric).to include('deployment:"cf-rabbitmq"')
    expect(metric).to include('eventType:ValueMetric')
    expect(metric).to match(/timestamp:\d/)
    expect(metric).to match(/index:"\d"/)
    expect(metric).to match(/ip:"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"/)

    regex_patterns.each do |expr|
      expect(metric).to match(expr)
    end
  end

  def find_metric(metric_name, job_name, job_index)
    start_time = DateTime.now

    31.times do
      File.open(firehose_out_file, "r") do |file|
        regex = /(?=.*name:"#{metric_name}")(?=.*job:"#{job_name}")(?=.*index:"#{job_index}")/
        matches = file.readlines.grep(regex)

        metrics = matches.select do |entry|
          timestamp = entry.match(/timestamp:\d+/)[0].delete('timestamp:')
          time = Time.at(timestamp.to_i/1e9).to_datetime
          time >= start_time
        end

        if metrics.size > 0
          return metrics[0]
        end
      end
      sleep 1
    end
    fail("metric '#{metric_name}' for job '#{job_name}' with index '#{job_index}' not found")
  end

  def firehose_out_file
    @outFile.path
  end
end
