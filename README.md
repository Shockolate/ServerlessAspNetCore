# Global Serverless ASP.NET Core #

This repository is an example of how to implement a multi-regional serverless ASP.NET WebAPI fronted by a singular global endpoint.

## How It Works ##

This uses CloudFormation to instantiate API Gateway and Lambda object in each specified region. Afterwards, CloudFormation is used again to instantiate Route53 RouteTables in a provided Hosted Zone to point towards the created API Gateway endpoints. What results is an endpoint that will route traffic, based upon latency, to the relevant API Gateway & Lambda.

The .NET Core tools are provided by the Amazon.Lambda.Tools NuGet package.

Cloud Formation stacks are handled by CloudFormationWrapper.

## What is required ##

### Environment ###

* AWS Credentials. Preferably as Environment Variables. See the [AWS Credential Chain](https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/setup-config.html) for more information.
* [Ruby](https://www.ruby-lang.org/en/downloads/) v2.1 or greater
* [.NET Core SDK](https://www.microsoft.com/net/download/windows) v2.0.3 or greater.
* [Visual Studio 2017](https://www.visualstudio.com/) (Optional)

### Configuration ###

These can be supplied by other CloudFormation Stacks, or specified in the Rakefile.rb

* Application Name
  * Unique in your AWS Account
* S3 Bucket to store the Deployment Package and the Template.
* A Hosted Zone
  * A Hosted Zone and requisite SSL Certifications must be provided:
    * Hosted Zone ID
    * Certification ARN for each region
* A Domain Name
  * Full Domain Name to which you would like your regional and multi-regional endpoints to be
* Normal Lambda Configurations (in serverless.infrastructure.json)
  * Security Group Ids
  * Subnet Ids
  * Runtime
  * Execution Role
  * etc...

## Workflow ##

1.  Install Bundler:
    * `gem install bundler`
2.  Install Gem Dependencies:
    * `bundle install`
3.  Install NuGet Dependencies:
    * `rake retrieve`
4.  Build the Solution:
    * `rake build`
    * Or build the solution in VS2017
5.  Run Tests:
    * `rake test`
    * Or your favorite VS Test Runner
6.  Create the deployment package:
    * `rake package`
6.  Deploy
    * `rake deploy_test`
    * `rake deploy_production`
