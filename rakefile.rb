require 'aws-sdk-cloudformation'
require 'aws-sdk-apigateway'
Aws.use_bundled_cert!
require 'cloudformation_wrapper'
require 'rake'
require 'rake/clean'

STDOUT.sync = true
STDERR.sync = true

APPLICATION_NAME = 'ServerlessAspNetCore'.freeze
DOMAIN_NAME = 'asp.shop.cimpress.io'.freeze

REGIONS = {
  'eu-west-1' => {
    certificate_arn: 'arn:aws:acm:eu-west-1:652754698884:certificate/f57c0940-b3df-42c0-8ba7-8df7db28e4e7'
  },
  'us-east-1' => {
    certificate_arn: '	arn:aws:acm:us-east-1:652754698884:certificate/878c7e9c-f809-4a18-b656-c777d4f8fccc'
  }
}

HOSTED_ZONE_ID = 'Z1OPPRMHHEDHI2'.freeze
ROOT = File.dirname(__FILE__)
SRC_DIR = File.join(ROOT, 'src')
PACKAGE_DIR = File.join(ROOT, 'package')
CONFIG_DIR = File.join(ROOT, 'config')
REPORTS_DIR = File.join(ROOT, 'reports')
REGIONAL_TEMPLATE_PATH = File.join(ROOT, 'regional.infrastructure.yaml')
GLOBAL_TEMPLATE_PATH = File.join(ROOT, 'global.infrastructure.yaml')
SERVERLESS_TEMPLATE_PATH = File.join(ROOT, 'serverless.infrastructure.json')

CLEAN.include(PACKAGE_DIR)
CLEAN.include(File.join(ROOT, 'reports'))
CLEAN.include(File.join(SRC_DIR, '**/bin'), File.join(SRC_DIR, '**/obj'), 'output')
CLEAN.include(REPORTS_DIR)

# Developer Tasks
desc 'Compiles source code to binaries.'
task :build => [:clean, :before_each, :retrieve, :dotnet_build]

desc 'Builds and runs tests.'
task :test => [:before_each, :build, :unit_test]

# Jenkins Tasks
task :pull_request_job => [:build, :test, :deploy_test]
task :merge_job => [:build, :test, :deploy_production]

# Workflow tasks
desc 'Retrieves external dependencies.'
task :retrieve => [:before_each] do
  cmd = 'dotnet restore ' \
  '--force ' \
  '--verbosity=normal ' \
  '/maxcpucount:1'
  puts "Executing Command: #{cmd}"
  raise 'Dependency installation failed.' unless system(cmd)
end

task :dotnet_build => [:before_each] do
  cmd = 'dotnet build ' \
  '--no-restore ' \
  '--framework=netcoreapp2.0 ' \
  '--verbosity=normal ' \
  '/maxcpucount:1'
  puts "Executing Command: #{cmd}"
  raise 'Error building solution.' unless system(cmd)
end

task :lint => [:before_each] do
  lint_code
  linting_results = parse_linting_results

  unless linting_results.empty?
    puts linting_results
    # ommitting the failure until R# Works with Jenkins.
    # raise 'Failed Linting.'
  end
end

task :before_each do
  FileUtils.mkdir(PACKAGE_DIR, verbose: true) unless Dir.exist?(PACKAGE_DIR)
  FileUtils.mkdir(REPORTS_DIR, verbose: true) unless Dir.exist?(REPORTS_DIR)
end

task :package => [:before_each] do
  Dir.chdir(File.join(SRC_DIR, APPLICATION_NAME)) do
    cmd = 'dotnet lambda package ' \
    '--configuration Release ' \
    '--framework netcoreapp2.0 ' \
    "--output_package #{File.join(PACKAGE_DIR, 'deployment_package.zip')} " \
    '/maxcpucount:1'
    puts "Executing command: #{cmd}"
    raise 'Error packaging.' unless system(cmd)
  end
end

task :deploy, [:environment] do |_, args|
  raise 'Parameter environment needs to be set' if args[:environment].nil?
  deploy_environment(args[:environment])
end

task :deploy_test do
  deploy_environment('test')
end

task :deploy_production do
  deploy_environment('production')
  deploy_global_infrastructure(Aws::CloudFormation::Client.new(region: 'eu-west-1'))
end

task :deploy_global_infrastructure do
  deploy_global_infrastructure(Aws::CloudFormation::Client.new(region: 'eu-west-1'))
end

def deploy_environment(environment)
  REGIONS.each do |region, config|
    puts
    puts
    puts "Deploying #{APPLICATION_NAME} to #{environment} in #{region}."
    deploy_region_environment(
      region, config, environment,
      Aws::CloudFormation::Client.new(region: region),
      Aws::APIGateway::Client.new(region: region)
    )
  end
end

def deploy_region_environment(region, region_config, environment, cf_client, apig_client)
  stack_name = APPLICATION_NAME
  Dir.chdir(File.join(SRC_DIR, APPLICATION_NAME)) do
    cmd = 'dotnet lambda deploy-serverless ' \
    "--region #{region} " \
    '--configuration Release ' \
    '--framework netcoreapp2.0 ' \
    "--package #{File.join(PACKAGE_DIR, 'deployment_package.zip')} " \
    "--s3-bucket shopfloor-artifacts-#{region} " \
    '--s3-prefix DeploymentPackages/ ' \
    "--template #{SERVERLESS_TEMPLATE_PATH} " \
    '--template-parameters ' \
      "ServiceNameParameter=#{APPLICATION_NAME};" \
      "EnvironmentParameter=#{environment} " \
    "--stack-name #{stack_name} " \
    '--stack-wait true '
    puts "Executing command: #{cmd}"
    raise 'Error deploying to environment!' unless system(cmd)
  end
  puts
  regional_apig_id = get_recently_deployed_apig_id(stack_name, cf_client)
  set_regional_endpoint_configuration(regional_apig_id, apig_client)
  return unless environment == 'production'
  deploy_regional_mapping(regional_apig_id, region_config[:certificate_arn], cf_client)
  REGIONS[region][:target_domain] = apig_client.get_domain_name(domain_name: DOMAIN_NAME).regional_domain_name
end

def get_recently_deployed_apig_id(stack_name, cf_client)
  cf_describe_response = cf_client.describe_stacks(stack_name: stack_name)
  raise 'Could not find singular newly created stack.' if cf_describe_response.stacks.length != 1

  apig_id = ''
  cf_describe_response.stacks[0].outputs.each do |output|
    apig_id = output.output_value if output.output_key == 'ApiId'
  end
  raise 'Could not determine ApiGateway ID' if apig_id.empty?
  apig_id
end

def set_regional_endpoint_configuration(apig_id, apig_client)
  current_endpoint_configuration = apig_client.get_rest_api(rest_api_id: apig_id).endpoint_configuration.types[0]
  if current_endpoint_configuration == "REGIONAL"
    puts 'API is already configured as Regional Endpoint'
    return
  end
  puts "Setting API #{apig_id} to Regional."
  update_params = {
    rest_api_id: apig_id,
    patch_operations: [
      {
        op: 'replace',
        path: '/endpointConfiguration/types/EDGE',
        value: 'REGIONAL'
      }
    ]
  }
  apig_client.update_rest_api(update_params)
  apig_id
end

def deploy_regional_mapping(apig_id, certificate_arn, cf_client)
  CloudFormationWrapper::StackManager.deploy(
    name: "#{APPLICATION_NAME}-mapping",
    client: cf_client,
    template_path: REGIONAL_TEMPLATE_PATH,
    wait_for_stack: true,
    parameters: {
      DomainNameParameter: DOMAIN_NAME,
      RegionalCertificateArnParameter: certificate_arn,
      RegionalApiIdParameter: apig_id
    }
  )
end

def deploy_global_infrastructure(cf_client)
  REGIONS.each do |region, config|
    unless config.key?(:target_domain)
      raise ArgumentError, "Region #{region} does not contain a target domain."
    end
  end

  CloudFormationWrapper::StackManager.deploy(
    name: "#{APPLICATION_NAME}-Global",
    client: cf_client,
    template_path: GLOBAL_TEMPLATE_PATH,
    wait_for_stack: true,
    parameters: {
      ServiceNameParameter: APPLICATION_NAME,
      HostedZoneIdParameter: HOSTED_ZONE_ID,
      MultiRegionEndpointParameter: DOMAIN_NAME,
      euwest1EndpointParameter: REGIONS['eu-west-1'][:target_domain],
      useast1EndpointParameter: REGIONS['us-east-1'][:target_domain]
    }
  )
end

def lint_code()
  cmd = "inspectcode \"#{Dir[File.join(ROOT, '*.sln')].first}\" --output=\"#{File.join(REPORTS_DIR, 'LintResults.xml')}\" --profile=\"#{Dir[File.join(ROOT, '*.sln.DotSettings')].first}\" --severity=WARNING --toolset=15.0".gsub!(/\//, '\\') # for some reason, inspectcode can't resolve the Forward Slash seperator.
  puts "Running Command: #{cmd}"
  output = `#{cmd}`
  puts output
  puts $?
  raise 'Error linting code.' unless $?.exitstatus.zero?
end

def parse_linting_results()
  lint_results_xml = Nokogiri::XML(File.open(File.join(REPORTS_DIR, 'LintResults.xml')))
  issue_types = Hash.new
  lint_results_xml.xpath("//IssueType").map do |issue_type_node|
    severity = issue_type_node['Severity']
    case severity
    when 'ERROR', 'WARNING'
      issue_types[issue_type_node['Id']] = Hash[:category => issue_type_node['Category'], :description => issue_type_node['Description'], :severity => severity]
    end
  end

  output_string = String.new
  lint_results_xml.xpath("//Issue").each do |issue_node|
    issue_type = issue_types[issue_node['TypeId']]
    unless issue_type.nil?
      output_string << issue_type[:severity] << ':' << "#{issue_type[:severity] == 'WARNING' ? "\t" : "\t\t"}"
      output_string << issue_type[:category] << "\t"
      output_string << issue_node['File'] << ':'

      if issue_node.key?('Line')
        output_string << issue_node['Line']
      else
        output_string << '0'
      end

      unless issue_type[:description].empty?
        output_string << " - #{issue_type[:description]}"
      end

      unless issue_node['Message'].empty?
        output_string << " - #{issue_node['Message']}"
      end

      output_string << "\n"
    end
  end
  output_string
end